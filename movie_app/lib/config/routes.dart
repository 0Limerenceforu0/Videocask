import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../pages/main_page.dart';
import '../pages/home/search_page.dart';
import '../pages/detail/detail_page.dart';
import '../pages/source/source_manager_page.dart';
import '../pages/cache/cache_manager_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/profile/profile_page.dart';
import '../pages/login/login_page.dart';
import '../pages/ranking/ranking_page.dart';
import '../pages/profile/stats_page.dart';
import '../pages/playlist/playlist_page.dart';
import '../pages/playlist/playlist_detail_page.dart';
import '../pages/follow/follow_page.dart';
import '../pages/design_reference/android_intro_design_v3_page.dart';
import '../models/movie.dart';
import '../models/cache_item.dart';
import '../models/watch_history.dart';
import '../utils/cache_playback_helper.dart';
import '../models/torrent_info.dart';
import '../services/torrent_search_service.dart';
import '../utils/torrent_title_display.dart';
import 'channel_portal_kind.dart';
import 'constants.dart';
import '../pages/channel/category_portal_page.dart';
import '../providers/movie_provider.dart';

Uri _normalizeIncomingDeepLink(Uri uri) {
  if (uri.scheme != 'movieapp') {
    return uri;
  }
  if (uri.host.isNotEmpty) {
    final seg = uri.host.startsWith('/') ? uri.host : '/${uri.host}';
    return Uri(
      path: seg,
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    );
  }
  if (uri.path.isEmpty) {
    return Uri(path: '/');
  }
  final p = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
  return Uri(
    path: p,
    queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
  );
}

/// 详情页路由 extra：兼容仅传 [Movie]，或带子字段的扩展参数
class DetailRouteExtra {
  final Movie? movie;
  final String? initialMagnetUri;

  /// 用户搜索时的中文片名（磁力详情补全元数据）
  final String? displayTitleHint;

  /// 磁力条目自带的 IMDb ID
  final String? torrentImdbId;

  /// 当前播放的磁力条目（详情页展示资源信息）
  final TorrentInfo? torrent;

  /// 从缓存列表进入详情时指定起播集数。
  final int? initialEpisodeIndex;

  const DetailRouteExtra({
    this.movie,
    this.initialMagnetUri,
    this.displayTitleHint,
    this.torrentImdbId,
    this.torrent,
    this.initialEpisodeIndex,
  });
}

/// 路由配置
class AppRoutes {
  AppRoutes._();

  /// 路由路径常量
  static const String home = '/';
  static const String search = '/search';
  static const String detail = '/detail';
  static const String sourceManager = '/source-manager';
  static const String cacheManager = '/cache-manager';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String login = '/login';
  static const String ranking = '/ranking';
  static const String stats = '/stats';
  static const String playlist = '/playlist';
  static const String playlistDetail = '/playlist/:id';
  static const String follow = '/follow';

  /// 设计稿 `design-v3-android-intro-collapsed-icons-only` 可交互复刻（静态演示）
  static const String designAndroidIntroV3 = '/design-android-intro-v3';

  /// DeepLink scheme
  static const String scheme = 'movieapp';

  /// 详情页路由观察（叠层详情时暂停底层播放等）
  static final RouteObserver<PageRoute<dynamic>> detailRouteObserver =
      RouteObserver<PageRoute<dynamic>>();

  /// 全局路由配置
  static final GoRouter router = GoRouter(
    initialLocation: home,
    debugLogDiagnostics: false,
    observers: [detailRouteObserver],
    routes: [
      // 首页（底部导航栏主框架）
      GoRoute(
        path: home,
        name: 'home',
        builder: (context, state) => const MainPage(),
      ),
      // 搜索页
      GoRoute(
        path: search,
        name: 'search',
        pageBuilder: _fadeUpBuilder((context, state) {
          final query = state.uri.queryParameters['query'] ?? '';
          return SearchPage(initialQuery: query);
        }),
      ),
      // 影片详情页
      GoRoute(
        path: detail,
        name: 'detail',
        pageBuilder: _fadeUpBuilder((context, state) {
          final movieId = state.uri.queryParameters['id'] ?? '';
          final sourceId = state.uri.queryParameters['sourceId'] ?? '';
          final extra = state.extra;
          Movie? movieArg;
          var initialMagnet = '';
          String? displayTitleHint;
          String? torrentImdbId;
          TorrentInfo? torrentArg;
          int? initialEpisodeIndex;
          if (extra is DetailRouteExtra) {
            movieArg = extra.movie;
            initialMagnet = extra.initialMagnetUri ?? '';
            displayTitleHint = extra.displayTitleHint;
            torrentImdbId = extra.torrentImdbId;
            torrentArg = extra.torrent;
            initialEpisodeIndex = extra.initialEpisodeIndex;
          } else if (extra is Movie) {
            movieArg = extra;
          }
          return DetailPage(
            movieId: movieId,
            sourceId: sourceId,
            movie: movieArg,
            initialMagnetUri: initialMagnet,
            displayTitleHint: displayTitleHint,
            torrentImdbId: torrentImdbId,
            torrent: torrentArg,
            initialEpisodeIndex: initialEpisodeIndex,
          );
        }),
      ),
      // 播放源管理
      GoRoute(
        path: sourceManager,
        name: 'sourceManager',
        pageBuilder:
            _fadeUpBuilder((context, state) => const SourceManagerPage()),
      ),
      // 缓存管理
      GoRoute(
        path: cacheManager,
        name: 'cacheManager',
        pageBuilder:
            _fadeUpBuilder((context, state) => const CacheManagerPage()),
      ),
      // 设置中心
      GoRoute(
        path: settings,
        name: 'settings',
        pageBuilder: _fadeUpBuilder((context, state) => const SettingsPage()),
      ),
      // 个人中心
      GoRoute(
        path: profile,
        name: 'profile',
        pageBuilder: _fadeUpBuilder((context, state) => const ProfilePage()),
      ),
      // 登录页
      GoRoute(
        path: login,
        name: 'login',
        pageBuilder: _fadeUpBuilder((context, state) => const LoginPage()),
      ),
      // 排行榜
      GoRoute(
        path: ranking,
        name: 'ranking',
        pageBuilder: _fadeUpBuilder((context, state) => const RankingPage()),
      ),
      // 观影统计
      GoRoute(
        path: stats,
        name: 'stats',
        pageBuilder: _fadeUpBuilder((context, state) => const StatsPage()),
      ),
      // 播放列表
      GoRoute(
        path: playlist,
        name: 'playlist',
        pageBuilder: _fadeUpBuilder((context, state) => const PlaylistPage()),
      ),
      // 播放列表详情
      GoRoute(
        path: playlistDetail,
        name: 'playlistDetail',
        pageBuilder: _fadeUpBuilder((context, state) {
          final id = state.pathParameters['id'] ?? '';
          return PlaylistDetailPage(playlistId: id);
        }),
      ),
      // 追剧（收藏 / 历史 / 缓存）
      GoRoute(
        path: follow,
        name: 'follow',
        pageBuilder: _fadeUpBuilder((context, state) => const FollowPage()),
      ),
      ...ChannelPortalKind.values.map(
        (k) => GoRoute(
          path: k.path,
          name: 'channel${k.name}',
          pageBuilder: _fadeUpBuilder(
            (context, state) => CategoryPortalPage(kind: k),
          ),
        ),
      ),
      GoRoute(
        path: designAndroidIntroV3,
        name: 'designAndroidIntroV3',
        pageBuilder: _fadeUpBuilder(
          (context, state) => const AndroidIntroDesignV3Page(),
        ),
      ),
    ],
    // 错误页面
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('页面未找到')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '页面 ${state.uri.path} 不存在',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go(home),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    ),
  );

  /// 统一转场动画构建器（返回 pageBuilder 所需的函数类型）
  static Page<void> Function(BuildContext, GoRouterState) _fadeUpBuilder(
    Widget Function(BuildContext, GoRouterState) builder,
  ) {
    return (context, state) => CustomTransitionPage<void>(
          child: builder(context, state),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeUpwardsTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              child: child,
            );
          },
        );
  }

  /// 根据 DeepLink URI 解析并跳转到对应页面
  ///
  /// 支持的格式：
  /// - movieapp://detail?id=123&sourceId=abc
  /// - movieapp://search?query=三体
  /// - movieapp://home
  /// 无 [BuildContext] 的深度链接入口（如 `app_links` 流），与 [handleDeepLink] 行为一致。
  static Future<void> handleDeepLinkForRouter(GoRouter router, Uri uri) async {
    final u = _normalizeIncomingDeepLink(uri);
    final path = u.path;
    final params = u.queryParameters;

    switch (path) {
      case '/detail':
      case 'detail':
        final id = params['id'] ?? '';
        final sourceId = params['sourceId'] ?? '';
        if (id.isNotEmpty) {
          final target = Uri(
            path: detail,
            queryParameters: <String, String>{
              'id': id,
              if (sourceId.isNotEmpty) 'sourceId': sourceId,
            },
          );
          await router.push(target.toString());
        }
        break;
      case '/search':
      case 'search':
        final query = params['query'] ?? '';
        final searchUri = Uri(
          path: search,
          queryParameters:
              query.isEmpty ? null : <String, String>{'query': query},
        );
        await router.push(searchUri.toString());
        break;
      case '/follow':
      case 'follow':
        await router.push(follow);
        break;
      case '/':
      case '':
      case '/home':
      case 'home':
        router.go(home);
        break;
      default:
        router.go(home);
    }
  }

  static Future<void> handleDeepLink(BuildContext context, Uri uri) async {
    await handleDeepLinkForRouter(GoRouter.of(context), uri);
  }

  // ========== 导航方法 ==========

  /// 导航到首页
  static void toHome(BuildContext context) {
    context.go(home);
  }

  /// 回首页并选中指定分类 Tab（通过 `?category=`，由首页消费后清掉 query）。
  static void toHomeWithCategory(BuildContext context, String category) {
    context.go(
      Uri(
        path: home,
        queryParameters: <String, String>{'category': category},
      ).toString(),
    );
  }

  /// 导航到搜索页
  static void toSearch(BuildContext context, {String query = ''}) {
    final uri = Uri(
      path: search,
      queryParameters: query.isEmpty ? null : <String, String>{'query': query},
    );
    context.push(uri.toString());
  }

  /// 导航到详情页
  static void toDetail(
    BuildContext context, {
    required String id,
    String sourceId = '',
    Movie? movie,
    String initialMagnetUri = '',
  }) {
    final uri = Uri.parse(detail).replace(
      queryParameters: <String, String>{
        'id': id,
        if (sourceId.isNotEmpty) 'sourceId': sourceId,
      },
    );
    final Object? extra = initialMagnetUri.isNotEmpty
        ? DetailRouteExtra(
            movie: movie,
            initialMagnetUri: initialMagnetUri,
          )
        : movie;
    context.push(uri.toString(), extra: extra);
  }

  /// 从已完成缓存进入详情离线播放（移动端）。
  static void toDetailFromCache(BuildContext context, CacheItem item) {
    final movie = CachePlaybackHelper.movieFromCacheItem(item);
    final uri = Uri.parse(detail).replace(
      queryParameters: <String, String>{
        'id': item.movieId,
        if (item.sourceId.isNotEmpty) 'sourceId': item.sourceId,
      },
    );
    context.push(
      uri.toString(),
      extra: DetailRouteExtra(
        movie: movie,
        initialEpisodeIndex: item.episodeIndex,
      ),
    );
  }

  /// 从观看历史进入详情（磁力源会带上 [WatchHistory.magnetUri] 以恢复播放）
  static void toDetailFromHistory(BuildContext context, WatchHistory h) {
    toDetail(
      context,
      id: h.movieId,
      sourceId: h.sourceId,
      movie: Movie(
        id: h.movieId,
        sourceId: h.sourceId,
        name: h.movieName,
        cover: h.movieCover,
        updateStatus: h.episodeName,
      ),
      initialMagnetUri:
          h.sourceId == AppConstants.magnetDetailSourceId ? h.magnetUri : '',
    );
  }

  /// 从片名中解析括号年份，如 `The Foo (1980)` → `1980`
  static String? yearInParentheses(String text) {
    final m = RegExp(r'\((\d{4})\)').firstMatch(text);
    return m?.group(1);
  }

  /// 打开「磁力资源」独立详情（返回栈回到上一页，一般为上一部影片详情）
  ///
  /// [enrichFrom] 为当前正在看的 CMS 详情时传入，可合并海报/简介/演职员到磁力页。
  static void toMagnetTorrentDetail(
    BuildContext context,
    TorrentInfo torrent, {
    Movie? enrichFrom,
    String? displayTitleHint,
  }) {
    final btih = TorrentSearchService.extractBtih(torrent.magnetUri) ??
        'h${torrent.magnetUri.hashCode.abs()}';
    final title = splitTorrentDisplayTitle(torrent.name);
    final magnetFooter = '——\n磁力索引：${torrent.source}';
    final torrentYear = yearInParentheses(torrent.name);

    final Movie movie;
    final canMergeCms = enrichFrom != null &&
        enrichFrom.sourceId != AppConstants.magnetDetailSourceId &&
        enrichFrom.sourceId.isNotEmpty;
    if (canMergeCms) {
      final releaseLine = <String>[
        if (title.primary.isNotEmpty) '资源标题：${title.primary}',
        if (title.secondary != null && title.secondary!.trim().isNotEmpty)
          '副标题：${title.secondary}',
      ].join('\n');
      final descBuf = StringBuffer();
      if (enrichFrom.description.trim().isNotEmpty) {
        descBuf.writeln(enrichFrom.description.trim());
        descBuf.writeln();
      }
      descBuf.writeln(magnetFooter);
      if (releaseLine.isNotEmpty) {
        descBuf.writeln();
        descBuf.writeln(releaseLine);
      }
      final aliasParts = <String>[
        if (title.primary.isNotEmpty &&
            title.primary.trim() != enrichFrom.name.trim())
          title.primary.trim(),
        if (title.secondary != null && title.secondary!.trim().isNotEmpty)
          title.secondary!.trim(),
        if (enrichFrom.alias.trim().isNotEmpty) enrichFrom.alias.trim(),
      ];
      movie = Movie(
        id: btih,
        sourceId: AppConstants.magnetDetailSourceId,
        name:
            enrichFrom.name.trim().isNotEmpty ? enrichFrom.name : title.primary,
        alias: aliasParts.join(' · '),
        cover: enrichFrom.cover.trim().isNotEmpty ? enrichFrom.cover : '',
        backdrop:
            enrichFrom.backdrop.trim().isNotEmpty ? enrichFrom.backdrop : '',
        rating: enrichFrom.rating,
        genres: enrichFrom.genres,
        region: enrichFrom.region,
        year: enrichFrom.year.trim().isNotEmpty
            ? enrichFrom.year
            : (torrentYear ?? ''),
        director: enrichFrom.director,
        actors: enrichFrom.actors,
        description: descBuf.toString(),
        playRoutes: const [],
      );
    } else {
      movie = Movie(
        id: btih,
        sourceId: AppConstants.magnetDetailSourceId,
        name: title.primary,
        alias: title.secondary ?? '',
        description: '磁力：${torrent.source}',
        year: torrentYear ?? '',
        playRoutes: const [],
      );
    }
    final uri = Uri.parse(detail).replace(
      queryParameters: <String, String>{
        'id': btih,
        'sourceId': AppConstants.magnetDetailSourceId,
      },
    );
    context.read<MovieProvider>().pushDetailSnapshot();
    context.push(
      uri.toString(),
      extra: DetailRouteExtra(
        movie: movie,
        initialMagnetUri: torrent.magnetUri,
        displayTitleHint: displayTitleHint,
        torrentImdbId: torrent.imdbId,
        torrent: torrent,
      ),
    );
  }

  /// 导航到设置页
  static void toSettings(BuildContext context) {
    context.push(settings);
  }

  /// 导航到个人中心
  static void toProfile(BuildContext context) {
    context.push(profile);
  }

  /// 导航到登录页
  static void toLogin(BuildContext context) {
    context.push(login);
  }

  /// 导航到播放源管理
  static void toSourceManager(BuildContext context) {
    context.push(sourceManager);
  }

  /// 导航到缓存管理
  static void toCacheManager(BuildContext context) {
    context.push(cacheManager);
  }

  /// 导航到排行榜
  static void toRanking(BuildContext context) {
    context.push(ranking);
  }

  /// 导航到观影统计
  static void toStats(BuildContext context) {
    context.push(stats);
  }

  /// 导航到播放列表
  static void toPlaylist(BuildContext context) {
    context.push(playlist);
  }

  /// 导航到追剧（收藏 / 历史 / 缓存）
  static void toFollow(BuildContext context) {
    context.push(follow);
  }

  /// 进入高保真频道占位页（电影 / 连续剧 / …）
  static void toChannelPortal(BuildContext context, ChannelPortalKind kind) {
    context.push(kind.path);
  }

  /// 打开 Android 详情设计稿复刻页
  static void toDesignAndroidIntroV3(BuildContext context) {
    context.push(designAndroidIntroV3);
  }

  /// 导航到播放列表详情
  static void toPlaylistDetail(
    BuildContext context, {
    required String playlistId,
  }) {
    context.push('/playlist/$playlistId');
  }
}

/// 自定义页面转场动画：向上淡入 + 从下方轻微滑入
class FadeUpwardsTransition extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const FadeUpwardsTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final position = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
    );

    final opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      ),
    );

    return SlideTransition(
      position: position,
      child: FadeTransition(
        opacity: opacity,
        child: child,
      ),
    );
  }
}

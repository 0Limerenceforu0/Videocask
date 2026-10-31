import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/web_http_stub.dart'
    if (dart.library.html) '../../utils/web_http.dart' as web_http;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../config/constants.dart';
import '../../config/channel_portal_kind.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/hifi_design_tokens.dart';
import '../../widgets/hifi_channel_nav_row.dart';
import '../../widgets/hifi_desktop_search_bar.dart';
import '../../widgets/hifi_desktop_toolbar.dart';
import '../../widgets/category_genre_region_filter_band.dart';
import '../../models/movie.dart';
import '../../models/watch_history.dart';
import '../../providers/movie_provider.dart';
import '../../providers/source_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/favorite_provider.dart';
import 'banner_widget.dart';
import 'movie_card.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/error_widget.dart' as app_widgets;
import '../../widgets/hifi_home_wide_portal_modules.dart';
import '../../widgets/movie_grid_layout.dart';

/// 首页 - 分区布局（横向滚动 + 高分推荐无限滚动）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  /// 当前选中的分类
  String _selectedCategory = '';

  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 是否正在刷新
  // ignore: unused_field
  bool _isRefreshing = false;

  /// 是否已加载过数据
  bool _hasLoaded = false;

  /// 是否已请求过个性化推荐（防止无限 rebuild 循环）
  bool _hasRequestedPersonalized = false;

  /// 当前使用的源ID（用于检测源切换）
  String _currentSourceId = '';

  // ===== 分区展开/收起状态 =====
  /// 最近更新是否展开
  bool _isLatestExpanded = false;

  /// 热门影视是否展开
  bool _isHotExpanded = false;

  /// 首页视图密度：true=紧凑（更多列），false=舒适（更大卡片）
  bool _denseMode = false;

  /// 分类 Tab 浏览：类型 / 地区（传参给 CMS 列表）
  String _filterGenre = '全部';
  String _filterRegion = '全部';

  /// 已调度处理的首页 `?category=` 完整 URI（避免 `didChangeDependencies` 重复入队）。
  String? _scheduledHomeCategoryQuerySignature;

  /// 是否显示「回顶部」悬浮按钮
  bool _showScrollToTop = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 监听滚动事件，实现高分推荐区域的无限滚动
    _scrollController.addListener(_onScroll);
    // 延迟到 build 完成后再加载数据，避免在 build 期间触发 notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasLoaded) {
        _loadData();
      }
    });
  }

  /// 滚动监听 - 提前加载更多（距底部约1-2屏时触发，实现无感刷新）
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    final showTop = pos.pixels > 320;
    if (showTop != _showScrollToTop && mounted) {
      setState(() => _showScrollToTop = showTop);
    }

    // 提前加载更多，当滚动到距离底部800像素时触发，实现无感刷新
    if (pos.pixels < pos.maxScrollExtent - 800) return;

    final movieProvider = context.read<MovieProvider>();
    if (!movieProvider.isLoadingMore) {
      if (_selectedCategory.isNotEmpty) {
        // 🔴 mergeSources 必须传（2026-10-21）：不传则 provider 内 enabled
        // 回退为空列表、续页退回单源，与多源合并的首屏口径不一致 →「滚着
        // 滚着列表全部切换」。
        movieProvider.loadCategoryMovies(
          category: _selectedCategory,
          region: _categoryRegionParam(),
          genre: _categoryGenreParam(),
          refresh: false,
          mergeSources: context.read<SourceProvider>().enabledSources,
        );
      } else {
        movieProvider.loadMoreHome();
      }
    }
  }

  String _categoryRegionParam() => _filterRegion == '全部' ? '' : _filterRegion;

  String _categoryGenreParam() => _filterGenre == '全部' ? '' : _filterGenre;

  /// 类型 / 地区切换：对已加载的分类列表做本地过滤，点完立刻见效。
  ///
  /// 采集站的 `ac=detail` 会忽略 `class` / `area` 参数，靠服务端筛是筛不动的。
  void _applyCategoryFilterLocally() {
    if (_selectedCategory.isEmpty) return;
    final provider = context.read<MovieProvider>();
    // 动态词表随已加载数据变化：已选词若不在当前可用词表里，必须回退到「全部」，
    // 否则会出现「chip 悬空选中」——UI 显示选着某个词，筛选却按另一个词在跑。
    final normalized = provider.normalizeSelectedFilters(
      genre: _filterGenre,
      region: _filterRegion,
    );
    if (normalized.genre != _filterGenre ||
        normalized.region != _filterRegion) {
      setState(() {
        _filterGenre = normalized.genre;
        _filterRegion = normalized.region;
      });
    }
    provider.setCategoryFilter(
      genre: normalized.genre,
      region: normalized.region,
    );
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _reloadCategoryFromFilters() {
    if (_selectedCategory.isEmpty) return;
    context.read<MovieProvider>().loadCategoryMovies(
          category: _selectedCategory,
          region: _categoryRegionParam(),
          genre: _categoryGenreParam(),
          refresh: true,
          mergeSources: context.read<SourceProvider>().enabledSources,
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  /// 高分推荐：先展示接口已按评分排好的 [MovieProvider.topRatedMovies]；
  /// 再将无限滚动追加的 [MovieProvider.homeMovies] 中有评分、且尚未出现的条目 **按加载顺序接在后面**，
  /// 避免与 topRated 合并后再全局按分排序导致「新加载的高分条顶到前面、把旧内容挤下去」。
  List<Movie> _mergeHighRatedMovies(MovieProvider movieProvider) {
    final seen = <String>{};
    final out = <Movie>[];
    for (final m in movieProvider.topRatedMovies) {
      if (m.rating > 0 && !seen.contains(m.id)) {
        seen.add(m.id);
        out.add(m);
      }
    }
    for (final m in movieProvider.homeMovies) {
      if (m.rating > 0 && !seen.contains(m.id)) {
        seen.add(m.id);
        out.add(m);
      }
    }
    return out;
  }

  /// 网格尾部：仅在正在加载更多、或已无更多数据时占一格；避免 hasMoreHome 且空闲时永远显示转圈
  bool _highRatedGridShowFooter(MovieProvider movieProvider) {
    return movieProvider.isLoadingMore || !movieProvider.hasMoreHome;
  }

  /// 加载数据
  Future<void> _loadData() async {
    final movieProvider = context.read<MovieProvider>();
    final sourceProvider = context.read<SourceProvider>();

    // 等待源初始化完成（如果还没初始化）
    if (sourceProvider.sources.isEmpty) {
      await sourceProvider.init();
    }

    // 确保有可用的源
    if (sourceProvider.currentSource != null) {
      movieProvider.setCurrentSource(sourceProvider.currentSource!);
    } else if (sourceProvider.sources.isNotEmpty) {
      // 如果没有currentSource但有源列表，强制选择第一个
      final firstSource = sourceProvider.sources.first;
      await sourceProvider.selectSource(firstSource.id);
      movieProvider.setCurrentSource(firstSource);
    }

    // 检测源是否切换，如果切换了则强制重新加载
    final newSourceId = sourceProvider.currentSource?.id ?? '';
    if (_hasLoaded &&
        _currentSourceId == newSourceId &&
        movieProvider.homeMovies.isNotEmpty) {
      return;
    }

    // 记录当前源ID
    _currentSourceId = newSourceId;

    // 换源后重新取数：类目 Tab 走分类列表（并派生分区），推荐 Tab 走全站首页。
    if (_selectedCategory.isEmpty) {
      await movieProvider.loadHomeData();
    } else {
      await movieProvider.loadCategoryMovies(
        category: _selectedCategory,
        region: '',
        genre: '',
        refresh: true,
        mergeSources: context.read<SourceProvider>().enabledSources,
      );
      movieProvider.deriveHomeSectionsFromCategory();
    }
    _hasLoaded = true;

    // 检查收藏影片的更新
    if (mounted) {
      final favoriteProvider = context.read<FavoriteProvider>();
      try {
        await favoriteProvider.checkForUpdatesFromApi(movieProvider);
      } catch (e) {
        debugPrint('检查更新失败: $e');
      }
    }

    // 显示源切换提示
    if (mounted) {
      final api = movieProvider.apiService;
      if (api.sourceSwitchMessages.isNotEmpty) {
        final lastMsg = api.sourceSwitchMessages.last;
        final switched = api.sourceSwitchMessages.any((m) => m.contains('切换到'));
        if (switched) {
          // 成功切换到其他源
          _showSourceMessage(lastMsg, isError: false);
        } else if (lastMsg.contains('所有源均无法')) {
          // 所有源都失败
          _showSourceMessage(lastMsg, isError: true);
        }
      }
    }
  }

  /// 显示源切换提示
  void _showSourceMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.swap_horiz,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade700 : Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: isError
            ? SnackBarAction(
                label: l10n.homeSnackbarRetry,
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  _onRefresh();
                },
              )
            : null,
      ),
    );
  }

  /// Web / 桌面宽屏顶栏：品牌 + 频道导航对齐高保真稿；其余宽度沿用「首页推荐」标题行。
  Widget _buildHomeAppBarTitle(BuildContext context, ThemeData theme) {
    final width = MediaQuery.sizeOf(context).width;
    final showDesktopShell = HiFiDesignTokens.useWideTopBarShell(context);
    final l10n = AppLocalizations.of(context)!;

    final actions = HiFiDesktopToolbar.trailingActions(
      context,
      denseMode: _denseMode,
      onToggleDenseMode: () => setState(() => _denseMode = !_denseMode),
      includeSearchIcon: !showDesktopShell,
    );

    return Row(
      children: [
        if (showDesktopShell) ...[
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: l10n.toolbarBrandGoHome,
                      child: InkWell(
                        onTap: () => unawaited(_onBrandTapHome()),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 2,
                          ),
                          child: Text(
                            l10n.appTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: HiFiDesignTokens.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const HiFiChannelNavRow(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 140,
                  maxWidth: math.min(480, width * 0.36),
                ),
                child: HiFiDesktopSearchBar(
                  hintText: l10n.toolbarSearchPlaceholderHome,
                ),
              ),
            ),
          ),
        ] else ...[
          Tooltip(
            message: l10n.toolbarBrandGoHome,
            child: InkWell(
              onTap: () => unawaited(_onBrandTapHome()),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                // 2026-10-28 用户反馈：左上角「推荐」文字和下方分类 Tab 的
                // 「推荐」重名，看不出这是「回首页」的品牌入口；随后又要求
                // 用**应用自己的图标**而不是随便一个 Material 图标。
                // `assets/images/app_icon.png` 就是 launcher 图标的副本。
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 28,
                  height: 28,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
          const Spacer(),
        ],
        ...actions,
      ],
    );
  }

  /// 在纵向 [CustomScrollView] 内为子树提供明确横向宽度（限 `shellMaxWidth`）。
  Widget _hifiScrollChildMaxWidth(
    BuildContext context, {
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var outer = constraints.maxWidth;
        if (!outer.isFinite || outer <= 0) {
          outer = MediaQuery.sizeOf(context).width;
        }
        if (!outer.isFinite || outer <= 0) {
          return const SizedBox.shrink();
        }
        final inner = math.min(outer, HiFiDesignTokens.shellMaxWidth);
        if (inner < 1) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          width: outer,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: inner, child: child),
          ),
        );
      },
    );
  }

  /// 宽屏推荐首页：对齐 `hifi-screen-home-windows.html`（门户模块 + 侧榜），不含第二行分类 Tab 下的旧分区。
  List<Widget> _buildWideHomeRecommendSlivers(BuildContext context) {
    return [
      SliverToBoxAdapter(
        child: _hifiScrollChildMaxWidth(
          context,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: _buildContinueWatchingSection(context),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _hifiScrollChildMaxWidth(
            context,
            child: const HiFiHomeWidePortalModules(),
          ),
        ),
      ),
      const SliverToBoxAdapter(
        child: SizedBox(height: 90),
      ),
    ];
  }

  /// 下拉刷新
  Future<void> _onRefresh() async {
    setState(() {
      _isRefreshing = true;
      _isLatestExpanded = false;
      _isHotExpanded = false;
    });

    if (_selectedCategory.isNotEmpty) {
      await context.read<MovieProvider>().loadCategoryMovies(
            category: _selectedCategory,
            region: _categoryRegionParam(),
            genre: _categoryGenreParam(),
            refresh: true,
            mergeSources: context.read<SourceProvider>().enabledSources,
          );
    } else {
      _hasLoaded = false;
      await _loadData();
    }

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _categoryTabController?.dispose();
    super.dispose();
  }

  MovieGridMetrics _movieGridMetrics(BuildContext context) {
    return MovieGridLayout.metricsForContext(
      context,
      dense: _denseMode,
    );
  }

  /// 分类选择
  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = category;
      _filterGenre = '全部';
      _filterRegion = '全部';
    });
    _syncCategoryTabToSelection();
    // 切 Tab 一律回到「精选」模式：只拉前 N 个子类，其余点小分类 chip 再拉。
    _loadCategoryTab(category);
  }

  /// 加载类目 Tab 数据（切 Tab 与点子分类 chip 共用）。
  ///
  /// [subClassId] 非空 = 只拉该子类（用户点了「小分类」chip）；
  /// [subClassAll] = 用户显式要「全部」，展开全部子类（请求量大，慎用）；
  /// 都不传 = 精选模式，只拉前 `ApiService.defaultSubClassCount` 个子类 ——
  /// 这是「最小代价」的关键：实测全展开一次切 Tab ≈ 60 个 961KB 请求。
  void _loadCategoryTab(
    String category, {
    int? subClassId,
    bool subClassAll = false,
  }) {
    final movieProvider = context.read<MovieProvider>();
    final mergeSources = context.read<SourceProvider>().enabledSources;
    Future<void> run() async {
      // 分类列表（唯一数据源）：轮播与各分区都从它派生，避免重复拉取。
      // ⚠️ 不要再调 `loadHomeData(category:)` —— 那是「每个子类各拉 5 页」，
      // 与分类列表叠加会让单次切 Tab 打出上百个请求（实测 343 个），必被限流。
      final pending = movieProvider.loadCategoryMovies(
        category: category,
        region: '',
        genre: '',
        refresh: true,
        subClassId: subClassId,
        subClassAll: subClassAll,
        mergeSources: mergeSources,
      );
      // loadCategoryMovies 的同步段已清空 `_categoryMovies`；立刻派生一次，
      // 把上一个类目的轮播先清掉 —— 否则新数据到达前这几秒 banner 仍是上个
      // 类目的内容（用户截图「动漫 Tab 顶部是剧集简介」有这个窗口期的份）。
      movieProvider.deriveHomeSectionsFromCategory();
      await pending;
      movieProvider.deriveHomeSectionsFromCategory();
    }

    run();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  /// 点「小分类」chip：只拉选中的子类（或精选 / 全部）。
  ///
  /// 同时重置类型/地区筛选 —— 子类本身就是最细的维度，叠加筛选容易得到空列表。
  void _selectSubClass(
      {int? subClassId, bool featured = false, bool all = false}) {
    if (_selectedCategory.isEmpty) return;
    setState(() {
      _filterGenre = '全部';
      _filterRegion = '全部';
    });
    _loadCategoryTab(
      _selectedCategory,
      subClassId: featured ? null : subClassId,
      subClassAll: all,
    );
  }

  /// 宽屏顶栏品牌（罐子）即首页：清空分类筛选并回到推荐态。
  Future<void> _onBrandTapHome() async {
    setState(() {
      _selectedCategory = '';
      _filterGenre = '全部';
      _filterRegion = '全部';
    });
    _syncCategoryTabToSelection();
    if (!context.mounted) return;
    context.go(AppRoutes.home);
    if (!context.mounted) return;
    await context.read<MovieProvider>().loadHomeData();
    if (!context.mounted) return;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// B站风格的分类Tab控制器
  TabController? _categoryTabController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 初始化分类Tab控制器
    if (_categoryTabController == null ||
        _categoryTabController!.length != AppConstants.categories.length + 1) {
      _categoryTabController?.dispose();
      _categoryTabController = TabController(
        length: AppConstants.categories.length + 1,
        vsync: this,
      );
      // 设置初始选中索引（0=推荐, 1..N=分类）
      if (_selectedCategory.isNotEmpty) {
        final idx = AppConstants.categories.indexOf(_selectedCategory);
        if (idx >= 0) {
          _categoryTabController!.index = idx + 1;
        }
      }
      _categoryTabController!.addListener(_onCategoryTabChanged);
    }
    _maybeConsumeHomeCategoryQuery();
  }

  void _syncCategoryTabToSelection() {
    final c = _categoryTabController;
    if (c == null) {
      return;
    }
    if (_selectedCategory.isEmpty) {
      if (c.index != 0) {
        c.index = 0;
      }
    } else {
      final idx = AppConstants.categories.indexOf(_selectedCategory);
      if (idx >= 0 && c.index != idx + 1) {
        c.index = idx + 1;
      }
    }
  }

  /// 消费 `/?category=电影` 等 deep link（频道页「更多」与外链）。
  void _maybeConsumeHomeCategoryQuery() {
    final go = GoRouter.maybeOf(context);
    if (go == null) {
      return;
    }
    final uri = go.routerDelegate.currentConfiguration.uri;
    final q = uri.queryParameters['category'];
    if (q == null || q.isEmpty) {
      _scheduledHomeCategoryQuerySignature = null;
      return;
    }
    if (!AppConstants.categories.contains(q)) {
      return;
    }
    final signature = uri.toString();
    if (_scheduledHomeCategoryQuerySignature == signature) {
      return;
    }
    _scheduledHomeCategoryQuerySignature = signature;
    final category = q;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _onCategorySelected(category);
      if (!mounted) {
        return;
      }
      final g = GoRouter.maybeOf(context);
      if (g != null &&
          g.routerDelegate.currentConfiguration.uri.queryParameters
              .containsKey('category')) {
        g.go(AppRoutes.home);
      }
      if (mounted) {
        _scheduledHomeCategoryQuerySignature = null;
      }
    });
  }

  /// 分类Tab切换回调
  void _onCategoryTabChanged() {
    if (_categoryTabController?.indexIsChanging == true) return;
    final index = _categoryTabController?.index ?? 0;
    if (index == 0) {
      if (_selectedCategory.isEmpty) return;
      setState(() {
        _selectedCategory = '';
        _filterGenre = '全部';
        _filterRegion = '全部';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await context.read<MovieProvider>().loadHomeData();
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    } else {
      final category = AppConstants.categories[index - 1];
      if (category != _selectedCategory) {
        _onCategorySelected(category);
      }
    }
  }

  // ===== 分区 UI 构建方法 =====

  /// 构建分区标题栏（B站风格：左侧粗体标题 + 右侧"查看更多 >"）
  ///
  /// [title] 分区标题
  /// [onMore] 点击"更多/收起"的回调，为 null 时不显示按钮
  /// [isExpanded] 当前是否展开
  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    VoidCallback? onMore,
    bool isExpanded = false,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          // 左侧装饰条
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          // 分区标题
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const Spacer(),
          // "查看更多 >"按钮（B站风格）
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              child: Row(
                children: [
                  Text(
                    isExpanded
                        ? l10n.homeSectionCollapse
                        : l10n.homeSectionSeeMore,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontSize: 13,
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.chevron_right,
                    size: 16,
                    color: theme.hintColor,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 构建横向滚动影片列表
  ///
  /// 卡片宽度约 130px，高度约 190px，显示封面 + 名称 + 评分
  Widget _buildHorizontalMovieList(List<Movie> movies) {
    final screenW = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenW * 0.30).clamp(104.0, 132.0);
    final cardHeight = cardWidth * 1.4;
    final listHeight = cardHeight + 56;
    return SizedBox(
      height: listHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: movies.length,
        // 增大缓存区域以提升横向滚动流畅度
        cacheExtent: 500,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: MovieCard(
              movie: movies[index],
              width: cardWidth,
              height: cardHeight,
            ),
          );
        },
      ),
    );
  }

  /// 构建展开后的竖向网格
  Widget _buildExpandedGrid(List<Movie> movies, BuildContext context) {
    final grid = _movieGridMetrics(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: grid.sliverDelegate,
        itemCount: movies.length,
        itemBuilder: (context, index) {
          return MovieCard(movie: movies[index]);
        },
      ),
    );
  }

  /// 构建可展开/收起的分区内容
  ///
  /// 收起时显示横向滚动卡片，展开时显示竖向网格，切换时有动画效果
  Widget _buildExpandableSection({
    required List<Movie> movies,
    required bool isExpanded,
    required BuildContext context,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: isExpanded
              ? _buildExpandedGrid(movies, context)
              : _buildHorizontalMovieList(movies),
        ),
        if (!isExpanded && movies.length > 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              '共 ${movies.length} 条 · 横向滑动可浏览全部',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  /// 构建分区加载失败重试提示
  Widget _buildSectionRetry(
    BuildContext context, {
    required VoidCallback onRetry,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: onRetry,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: theme.hintColor,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.homeLoadFailedTapRetry,
              style: TextStyle(
                color: theme.hintColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建高分推荐卡片（与分类网格一致使用 MovieCard 评分角标）
  Widget _buildHighRatedCard(BuildContext context, Movie movie) {
    String? origin;
    if (movie.sourceId.isNotEmpty) {
      for (final s in context.read<SourceProvider>().sources) {
        if (s.id == movie.sourceId) {
          origin = s.name;
          break;
        }
      }
    }
    return MovieCard(movie: movie, originLabel: origin);
  }

  // ===== 分类 Tab 浏览：筛选条（类型 + 地区） =====

  /// 与顶栏「电影 / 连续剧…」频道路由对应的 CMS 分类 Tab（纪录片暂无独立频道）。
  ChannelPortalKind? _channelKindForHomeCategory(String category) {
    return switch (category) {
      '电影' => ChannelPortalKind.movies,
      '剧集' => ChannelPortalKind.tv,
      '综艺' => ChannelPortalKind.variety,
      '动漫' => ChannelPortalKind.anime,
      _ => null,
    };
  }

  Widget _buildCategoryFilterBand(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final channelKind = _channelKindForHomeCategory(_selectedCategory);
    final movieProvider = context.watch<MovieProvider>();

    // 采集源的列表接口普遍不返回 `vod_class` / `vod_area`（2026-10-21 实测 lzi / ffzy
    // 的 `ac=list` 只有 8 个字段，加 `h` 也无效），此时类型/地区筛选无法生效 ——
    // 与其让用户以为「只有几条」，不如明说。
    final filterSelected = _filterGenre != '全部' || _filterRegion != '全部';
    final filterIneffective = filterSelected &&
        movieProvider.categoryUnsupported == false &&
        !movieProvider.categoryHasFilterMetadata;

    // 「小分类」行：切 Tab 只拉前 N 个子类（见 ApiService.defaultSubClassCount），
    // 点这里按需只拉选中的子类 —— 一次切 Tab 从 ~60 个 961KB 请求降到 ~15 个。
    final subClasses = movieProvider.categorySubClasses;
    final selectedSubClassId = movieProvider.selectedSubClassId;
    String selectedSubClass = CategoryGenreRegionFilterBand.kSubClassFeatured;
    if (movieProvider.subClassAll) {
      selectedSubClass = CategoryGenreRegionFilterBand.kSubClassAll;
    } else if (selectedSubClassId != null) {
      for (final n in subClasses) {
        if (n.id == selectedSubClassId) {
          selectedSubClass = n.name;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CategoryGenreRegionFilterBand(
          category: _selectedCategory,
          selectedGenre: _filterGenre,
          selectedRegion: _filterRegion,
          genreOptions: movieProvider.categoryGenreOptions,
          regionOptions: movieProvider.categoryRegionOptions,
          subClassItems: subClasses.map((n) => n.name).toList(growable: false),
          selectedSubClass: selectedSubClass,
          onSubClassSelected: (v) {
            if (v == CategoryGenreRegionFilterBand.kSubClassFeatured) {
              if (movieProvider.subClassAll || selectedSubClassId != null) {
                _selectSubClass(featured: true);
              }
              return;
            }
            if (v == CategoryGenreRegionFilterBand.kSubClassAll) {
              if (!movieProvider.subClassAll) _selectSubClass(all: true);
              return;
            }
            for (final n in subClasses) {
              if (n.name == v && n.id != selectedSubClassId) {
                _selectSubClass(subClassId: n.id);
                break;
              }
            }
          },
          onGenreSelected: (v) {
            if (v == _filterGenre) return;
            setState(() => _filterGenre = v);
            _applyCategoryFilterLocally();
          },
          onRegionSelected: (v) {
            if (v == _filterRegion) return;
            setState(() => _filterRegion = v);
            _applyCategoryFilterLocally();
          },
          header: channelKind == null
              ? null
              : Align(
                  alignment: Alignment.centerRight,
                  child: Tooltip(
                    message: l10n.homeOpenDedicatedChannelTooltip,
                    child: TextButton.icon(
                      icon: const Icon(Icons.dashboard_customize_outlined,
                          size: 18),
                      label: Text(l10n.homeOpenDedicatedChannel),
                      onPressed: () =>
                          AppRoutes.toChannelPortal(context, channelKind),
                    ),
                  ),
                ),
        ),
        if (filterIneffective)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: Theme.of(context).hintColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.homeCategoryFilterUnavailable,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  bool _categoryGridShowFooter(MovieProvider p) {
    final movies = p.categoryMovies;
    if (movies.isEmpty) return false;
    return p.isLoadingMore || !p.hasMoreCategory;
  }

  // ===== 继续观看分区 =====

  /// 构建"继续观看"横向滚动分区
  ///
  /// 从 HistoryProvider 获取最近的观看记录（最多10条），按观看时间倒序排列。
  /// 每个卡片显示封面、进度条、集数信息，点击跳转到详情页。
  Widget _buildContinueWatchingSection(BuildContext context) {
    final theme = Theme.of(context);
    final historyProvider = context.watch<HistoryProvider>();

    // 获取最近10条观看记录
    final watchHistory = historyProvider.histories.take(10).toList();

    if (watchHistory.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        // 分区标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              // 左侧装饰条
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              // 分区标题
              Text(
                l10n.homeContinueWatching,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const Spacer(),
              // 查看全部按钮
              GestureDetector(
                onTap: () => AppRoutes.toProfile(context),
                child: Row(
                  children: [
                    Text(
                      l10n.homeContinueWatchingSeeAll,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                        fontSize: 13,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.hintColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 横向滚动卡片列表
        SizedBox(
          height: 245,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: watchHistory.length,
            cacheExtent: 500,
            itemBuilder: (context, index) {
              return _buildContinueWatchingCard(
                context,
                history: watchHistory[index],
                theme: theme,
              );
            },
          ),
        ),
      ],
    );
  }

  /// 构建"继续观看"单个卡片
  ///
  /// 显示封面图、半透明进度条、集数信息、影片名称
  /// 如果收藏的影片有更新，显示"更新"角标
  Widget _buildContinueWatchingCard(
    BuildContext context, {
    required WatchHistory history,
    required ThemeData theme,
  }) {
    const cardWidth = 160.0;
    const cardHeight = 200.0;

    // 计算进度百分比
    final progressPercent = history.progressPercent;
    final percentText = '${(progressPercent * 100).toStringAsFixed(0)}%';

    // 检查是否有更新
    final favoriteProvider = context.watch<FavoriteProvider>();
    final hasUpdate = favoriteProvider.hasUpdate(
      history.movieId,
      sourceId: history.sourceId,
    );

    return GestureDetector(
      onTap: () {
        // 跳转到详情页（带占位 Movie：无 playRoutes 仍会走接口；同时先切换 history 对应源）
        AppRoutes.toDetailFromHistory(context, history);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          width: cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面区域（带进度条叠加）
              Stack(
                children: [
                  // 封面图
                  Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: history.movieCover.isNotEmpty
                        ? Hero(
                            tag:
                                'history_${history.movieId}_${history.sourceId}',
                            child: CachedNetworkImage(
                              imageUrl: web_http.webProxiedImageUrl(
                                history.movieCover,
                              ),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    theme.colorScheme.primary
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Center(
                                child: Icon(
                                  Icons.movie_outlined,
                                  size: 36,
                                  color: theme.hintColor.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.movie_outlined,
                              size: 36,
                              color: theme.hintColor.withValues(alpha: 0.4),
                            ),
                          ),
                  ),

                  // 底部渐变遮罩
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 播放图标
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),

                  // 左下角集数信息
                  Positioned(
                    left: 6,
                    bottom: 28,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        history.episodeName.isNotEmpty
                            ? history.episodeName
                            : '第${history.episodeIndex + 1}集',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  // 右下角进度百分比
                  Positioned(
                    right: 6,
                    bottom: 28,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        percentText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // 底部进度条（B站风格：主题色细线）
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      child: LinearProgressIndicator(
                        value: progressPercent,
                        minHeight: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),

                  // 更新角标
                  if (hasUpdate)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '更新',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // 影片名称
              SizedBox(
                width: cardWidth,
                child: Text(
                  history.movieName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== 排行榜入口 =====

  /// 构建排行榜入口按钮
  Widget _buildRankingEntry(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GestureDetector(
        onTap: () => AppRoutes.toRanking(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.1),
                theme.colorScheme.primary.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              // 排行榜图标
              Icon(
                Icons.emoji_events,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              // 标题和描述
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '排行榜',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '好评榜 / 热播榜 / 最新榜 / 飙升榜',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // 箭头
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== 个性化推荐分区 =====

  /// 构建"猜你喜欢"个性化推荐分区
  ///
  /// 基于用户的观看历史和收藏中的类型偏好，从所有影片中筛选推荐。
  /// 仅在有观看历史或收藏时显示。
  Widget _buildPersonalizedSection(BuildContext context) {
    final theme = Theme.of(context);
    final movieProvider = context.watch<MovieProvider>();
    final historyProvider = context.watch<HistoryProvider>();
    final favoriteProvider = context.watch<FavoriteProvider>();

    // 如果没有观看历史和收藏，不显示此分区
    if (historyProvider.histories.isEmpty &&
        favoriteProvider.favorites.isEmpty) {
      return const SizedBox.shrink();
    }

    // 收集已观看和已收藏的影片ID和类型
    final watchedIds = <String>{};
    final favoriteIds = <String>{};
    // 注意：观看历史模型中没有类型字段，所以类型偏好仅从收藏中获取
    final favoriteGenres = <String>[];

    for (final h in historyProvider.histories) {
      watchedIds.add(h.movieId);
    }
    for (final f in favoriteProvider.favorites) {
      favoriteIds.add(f.movieId);
      favoriteGenres.addAll(f.genres);
    }

    // 首次加载或数据变化时计算推荐（仅请求一次，防止无限循环）
    if (!_hasRequestedPersonalized &&
        movieProvider.personalizedRecommendations.isEmpty) {
      _hasRequestedPersonalized = true;
      // 使用 WidgetsBinding 延迟执行，避免在 build 中触发 notifyListeners
      WidgetsBinding.instance.addPostFrameCallback((_) {
        movieProvider.getPersonalizedRecommendations(
          watchedMovieIds: watchedIds,
          favoriteMovieIds: favoriteIds,
          favoriteGenres: favoriteGenres,
        );
      });
    }

    final recommendations = movieProvider.personalizedRecommendations;

    if (recommendations.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        // 分区标题栏（B站风格）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              // 左侧装饰条
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '猜你喜欢',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
        // 横向滚动卡片列表
        SizedBox(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: recommendations.length,
            cacheExtent: 500,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: MovieCard(
                  movie: recommendations[index],
                  width: 130,
                  height: 190,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final movieProvider = context.watch<MovieProvider>();
    final sourceProvider = context.watch<SourceProvider>();

    // 检测源是否切换，如果切换了则重新加载
    final newSourceId = sourceProvider.currentSource?.id ?? '';
    if (_currentSourceId.isNotEmpty && _currentSourceId != newSourceId) {
      _currentSourceId = newSourceId;
      _hasLoaded = false;
      _hasRequestedPersonalized = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_selectedCategory.isNotEmpty) {
          _reloadCategoryFromFilters();
        } else {
          _loadData();
        }
      });
    }

    // 检查是否有任何数据可用（用于判断是否显示加载/错误状态）
    // 含轮播与高分预计算数据，避免仅有 banner/topRated 时误判为全无数据而长时间骨架屏
    final hasAnyData = movieProvider.latestMovies.isNotEmpty ||
        movieProvider.hotMovies.isNotEmpty ||
        movieProvider.homeMovies.isNotEmpty ||
        movieProvider.bannerList.isNotEmpty ||
        movieProvider.topRatedMovies.isNotEmpty;

    // ===== 准备分区数据 =====

    // 最近更新：使用 Provider 中的 latestMovies
    final latestMovies = movieProvider.latestMovies;

    // 热门影视：使用 Provider 中的 hotMovies
    final hotMovies = movieProvider.hotMovies;

    // 高分推荐：topRatedMovies（多页合并）+ homeMovies 追加，去重按分排序
    final highRatedMovies = _mergeHighRatedMovies(movieProvider);
    final useWideTopBarShell = HiFiDesignTokens.useWideTopBarShell(context);

    return Scaffold(
      floatingActionButton: _showScrollToTop
          ? Padding(
              padding: EdgeInsets.only(
                bottom: (!kIsWeb &&
                        (Theme.of(context).platform == TargetPlatform.android ||
                            Theme.of(context).platform == TargetPlatform.iOS))
                    ? 56 + MediaQuery.of(context).padding.bottom
                    : 0,
              ),
              child: FloatingActionButton.small(
                heroTag: 'home_scroll_top',
                tooltip: l10n.homeScrollToTopTooltip,
                onPressed: () {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                child: const Icon(Icons.vertical_align_top_rounded),
              ),
            )
          : null,
      body: RefreshIndicator(
        // B站风格圆形loading指示器
        color: theme.colorScheme.primary,
        backgroundColor: theme.colorScheme.surface,
        onRefresh: _onRefresh,
        child: CustomScrollView(
          controller: _scrollController,
          // 桌面/Web 下内容可能短于视口；无此 physics 时 RefreshIndicator + Viewport 易出现 geometry 为 null。
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ===== 顶部栏（固定在顶部，不随滚动消失） =====
            SliverAppBar(
              pinned: true,
              floating: false,
              elevation: 0,
              backgroundColor: theme.scaffoldBackgroundColor,
              title: _buildHomeAppBarTitle(context, theme),
              // 宽屏顶栏对齐高保真稿：频道在顶栏，不再显示第二行分类 Tab。
              bottom: useWideTopBarShell
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(44),
                      child: Container(
                        color: theme.scaffoldBackgroundColor,
                        child: TabBar(
                          controller: _categoryTabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
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
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          dividerColor: Colors.transparent,
                          tabs: [
                            Tab(text: l10n.homeTabRecommend),
                            ...AppConstants.categories.map((c) => Tab(text: c)),
                          ],
                        ),
                      ),
                    ),
            ),

            // ===== 轮播Banner（保留，精选 + 最新更新） =====
            SliverToBoxAdapter(
              child: useWideTopBarShell
                  ? _hifiScrollChildMaxWidth(
                      context,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: BannerWidget(
                          movies: movieProvider.bannerList,
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: BannerWidget(
                        movies: movieProvider.bannerList,
                      ),
                    ),
            ),

            // ===== 分类 Tab：筛选 + 网格（与「推荐」内容互斥） =====
            if (_selectedCategory.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _buildCategoryFilterBand(context),
              ),
              if (movieProvider.isLoading &&
                  movieProvider.categoryMovies.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (movieProvider.categoryMovies.isEmpty &&
                  movieProvider.errorMessage.isNotEmpty)
                SliverFillRemaining(
                  child: app_widgets.ErrorWidget(
                    message: movieProvider.errorMessage,
                    onRetry: _reloadCategoryFromFilters,
                  ),
                )
              else if (movieProvider.categoryMovies.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      '暂无影片，可尝试更换类型或地区筛选',
                      style: TextStyle(color: theme.hintColor, fontSize: 14),
                    ),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid(
                    gridDelegate: _movieGridMetrics(context).sliverDelegate,
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final list = movieProvider.categoryMovies;
                        final m = list[index];
                        String? origin;
                        if (m.sourceId.isNotEmpty) {
                          for (final s
                              in context.read<SourceProvider>().sources) {
                            if (s.id == m.sourceId) {
                              origin = s.name;
                              break;
                            }
                          }
                        }
                        return MovieCard(movie: m, originLabel: origin);
                      },
                      childCount: movieProvider.categoryMovies.length,
                    ),
                  ),
                ),
                if (_categoryGridShowFooter(movieProvider))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: movieProvider.isLoadingMore
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                AppLocalizations.of(context)!.homeEndOfListHint,
                                style: TextStyle(
                                  color: theme.hintColor,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ),
                  ),
              ],
            ]
            // ===== 推荐首页：加载状态 =====
            else if (movieProvider.isLoading && !hasAnyData)
              const SliverFillRemaining(
                child: HomeShimmer(),
              )
            else if (movieProvider.errorMessage.isNotEmpty && !hasAnyData)
              SliverFillRemaining(
                child: app_widgets.ErrorWidget(
                  message: movieProvider.errorMessage,
                  onRetry: _loadData,
                ),
              )
            else if (useWideTopBarShell)
              ..._buildWideHomeRecommendSlivers(context)
            else ...[
              // ===== 继续观看（横向滚动，在Banner之后、其他分区之前） =====
              SliverToBoxAdapter(
                child: _buildContinueWatchingSection(context),
              ),

              // ===== 排行榜入口 =====
              SliverToBoxAdapter(
                child: _buildRankingEntry(context),
              ),

              // ===== 最近更新（横向滚动，可展开） =====
              if (latestMovies.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    context,
                    title: '最近更新',
                    onMore: () => setState(() {
                      _isLatestExpanded = !_isLatestExpanded;
                    }),
                    isExpanded: _isLatestExpanded,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildExpandableSection(
                    movies: latestMovies,
                    isExpanded: _isLatestExpanded,
                    context: context,
                  ),
                ),
              ] else if (movieProvider.latestError.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    context,
                    title: '最近更新',
                    onMore: null,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildSectionRetry(
                    context,
                    onRetry: () => movieProvider.retryHomeSection('latest'),
                  ),
                ),
              ],

              // ===== 热门影视（横向滚动，可展开） =====
              if (hotMovies.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    context,
                    title: '热门影视',
                    onMore: () => setState(() {
                      _isHotExpanded = !_isHotExpanded;
                    }),
                    isExpanded: _isHotExpanded,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildExpandableSection(
                    movies: hotMovies,
                    isExpanded: _isHotExpanded,
                    context: context,
                  ),
                ),
              ] else if (movieProvider.hotError.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    context,
                    title: '热门影视',
                    onMore: null,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildSectionRetry(
                    context,
                    onRetry: () => movieProvider.retryHomeSection('hot'),
                  ),
                ),
              ],

              // ===== 猜你喜欢（个性化推荐，在排行榜入口之后） =====
              SliverToBoxAdapter(
                child: _buildPersonalizedSection(context),
              ),

              // ===== 高分推荐（竖向网格，无限滚动加载更多） =====
              if (highRatedMovies.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    context,
                    title: '高分推荐',
                    // 高分推荐没有"更多"按钮，使用无限滚动加载更多
                    onMore: null,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid(
                    gridDelegate: _movieGridMetrics(context).sliverDelegate,
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return _buildHighRatedCard(
                          context,
                          highRatedMovies[index],
                        );
                      },
                      childCount: highRatedMovies.length,
                    ),
                  ),
                ),
                if (_highRatedGridShowFooter(movieProvider))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: movieProvider.isLoadingMore
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                AppLocalizations.of(context)!.homeEndOfListHint,
                                style: TextStyle(
                                  color: theme.hintColor,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ),
                  ),
              ] else if (movieProvider.topRatedError.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    context,
                    title: '高分推荐',
                    onMore: null,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildSectionRetry(
                    context,
                    onRetry: () => movieProvider.retryHomeSection('topRated'),
                  ),
                ),
              ],

              // 如果所有分区都为数据，显示空状态提示
              if (latestMovies.isEmpty &&
                  hotMovies.isEmpty &&
                  highRatedMovies.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.movie_outlined,
                            size: 56,
                            color: theme.hintColor.withValues(alpha: 0.65),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '暂无影片数据',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.hintColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '请检查网络或播放源是否可用，也可进入播放源管理添加、启用数据源。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.hintColor.withValues(alpha: 0.85),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.tonal(
                            onPressed: () => AppRoutes.toSourceManager(context),
                            child: const Text('播放源管理'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],

            // 底部间距
            const SliverToBoxAdapter(
              child: SizedBox(height: 90),
            ),
          ],
        ),
      ),
    );
  }
}

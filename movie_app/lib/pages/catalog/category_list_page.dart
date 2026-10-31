import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/movie.dart';
import '../../providers/movie_provider.dart';
import '../../providers/source_provider.dart';
import '../../widgets/category_genre_region_filter_band.dart';
import '../../widgets/error_widget.dart' as app_widgets;
import '../../widgets/movie_grid_layout.dart';
import '../home/movie_card.dart';

/// 单个 CMS 分类的完整列表页（电影 / 剧集 / 综艺 / 动漫 / 短剧）。
///
/// 入口：首页宽屏模块、频道页模块标题右侧的「更多」按钮。
/// 与频道页的「三模块 + 右榜」布局不同，这里只呈现一个类目，
/// 支持「类型 / 地区」筛选与无限滚动加载。
class CategoryListPage extends StatefulWidget {
  const CategoryListPage({
    super.key,
    required this.category,
    this.initialGenre = '全部',
    this.initialRegion = '全部',
  });

  /// CMS 大类名（「电影」「短剧」…）
  final String category;

  final String initialGenre;
  final String initialRegion;

  @override
  State<CategoryListPage> createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_reload()));
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  String _param(String v) => (v == '全部' || v.isEmpty) ? '' : v;

  Future<void> _reload() async {
    if (!mounted) return;
    final provider = context.read<MovieProvider>();
    final sources = context.read<SourceProvider>().enabledSources;
    await provider.loadCategoryMovies(
      category: widget.category,
      region: _param(widget.initialRegion),
      genre: _param(widget.initialGenre),
      refresh: true,
      mergeSources: sources,
    );
    if (mounted && _controller.hasClients) {
      _controller.jumpTo(0);
    }
  }

  Future<void> _loadMore() async {
    if (!mounted) return;
    final provider = context.read<MovieProvider>();
    if (provider.isLoadingMore || !provider.hasMoreCategory) return;
    await provider.loadCategoryMovies(
      category: widget.category,
      refresh: false,
      mergeSources: context.read<SourceProvider>().enabledSources,
    );
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.pixels < pos.maxScrollExtent - 600) return;
    unawaited(_loadMore());
  }

  Widget _card(BuildContext context, Movie movie) {
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

  List<Widget> _slivers(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    MovieProvider provider,
    List<Movie> movies,
  ) {
    if (provider.isLoading && movies.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (movies.isEmpty && provider.errorMessage.isNotEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: app_widgets.ErrorWidget(
            message: provider.errorMessage,
            onRetry: _reload,
          ),
        ),
      ];
    }
    if (movies.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                // 该源没有此分类（如站点没有「短剧」）时给换源提示，而不是空列表。
                provider.categoryUnsupported
                    ? l10n.categoryPortalEmptyHint
                    : l10n.categoryPortalModuleEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.hintColor,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ];
    }

    final metrics = MovieGridLayout.metricsForContext(context);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        sliver: SliverGrid(
          gridDelegate: metrics.sliverDelegate,
          delegate: SliverChildBuilderDelegate(
            (context, index) => _card(context, movies[index]),
            childCount: movies.length,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: provider.isLoadingMore
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    provider.hasMoreCategory
                        ? l10n.categoryPortalScrollForMore
                        : l10n.homeEndOfListHint,
                    style: TextStyle(color: theme.hintColor, fontSize: 13),
                  ),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 60)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<MovieProvider>();
    final movies = provider.categoryMovies;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.category,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CategoryGenreRegionFilterBand(
              category: widget.category,
              selectedGenre: provider.categoryGenreFilter,
              selectedRegion: provider.categoryRegionFilter,
              // 采集站不认 class / area 参数，筛选在本地做，点击立即生效。
              onGenreSelected: (v) => provider.setCategoryFilter(genre: v),
              onRegionSelected: (v) => provider.setCategoryFilter(region: v),
            ),
            Expanded(
              child: RefreshIndicator(
                color: theme.colorScheme.primary,
                onRefresh: _reload,
                child: CustomScrollView(
                  controller: _controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: _slivers(context, theme, l10n, provider, movies),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

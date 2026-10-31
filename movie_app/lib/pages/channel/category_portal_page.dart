import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/category_filter_catalog.dart';
import '../../config/channel_portal_kind.dart';
import '../../config/routes.dart';
import '../../config/channel_portal_module_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../models/movie.dart';
import '../../providers/movie_provider.dart';
import '../../providers/source_provider.dart';
import '../../services/cms_category_resolver.dart';
import '../../theme/hifi_design_tokens.dart';
import '../../widgets/category_genre_region_filter_band.dart';
import '../../widgets/hifi_channel_nav_row.dart';
import '../../widgets/hifi_desktop_search_bar.dart';
import '../../widgets/hifi_desktop_toolbar.dart';
import 'widgets/category_portal_module_row.dart';

/// 宽屏频道页：全宽筛选 + 纵向三模块（各模块独立 `genre` 请求 + 右榜）；首模块支持分页。
class CategoryPortalPage extends StatefulWidget {
  const CategoryPortalPage({super.key, required this.kind});

  final ChannelPortalKind kind;

  @override
  State<CategoryPortalPage> createState() => _CategoryPortalPageState();
}

class _ChannelSlot {
  List<Movie> movies = [];
  int nextPage = 1;
  bool hasMore = false;
  bool loading = false;
  bool appending = false;
  String? error;

  /// 请求代际：切换筛选 / 刷新后自增，旧请求返回时按代际丢弃，避免覆盖新结果。
  int generation = 0;
}

class _CategoryPortalPageState extends State<CategoryPortalPage> {
  final ScrollController _scrollController = ScrollController();
  final List<_ChannelSlot> _slots = List.generate(3, (_) => _ChannelSlot());

  String _filterGenre = '全部';
  String _filterRegion = '全部';

  String _genreParam() => _filterGenre == '全部' ? '' : _filterGenre;

  String _regionParam() => _filterRegion == '全部' ? '' : _filterRegion;

  @override
  void initState() {
    super.initState();
    for (final s in _slots) {
      s.loading = true;
    }
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadAllModules());
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAllModules() async {
    for (var i = 0; i < 3; i++) {
      if (!mounted) return;
      await _fetchSlot(i, refresh: true);
    }
  }

  String? _fixedGenreForSlot(int i) {
    return ChannelPortalModuleCatalog.fixedGenres(widget.kind)[i];
  }

  String _genreForApiRequest(int i) {
    final fixed = _fixedGenreForSlot(i);
    return fixed ?? _genreParam();
  }

  /// 追加分页数据时按「名称 + 年份」去重，避免同一部片反复出现（曾出现「一直刷新重复剧情」）。
  static List<Movie> _appendDedup(List<Movie> base, List<Movie> more) {
    if (more.isEmpty) return base;
    final seen = <String>{
      for (final m in base) '${m.name.toLowerCase().trim()}|${m.year}',
    };
    final out = List<Movie>.from(base);
    for (final m in more) {
      if (seen.add('${m.name.toLowerCase().trim()}|${m.year}')) out.add(m);
    }
    return out;
  }

  Future<void> _fetchSlot(int i, {required bool refresh}) async {
    final slot = _slots[i];
    if (refresh) {
      // 用户主动切筛选 / 下拉刷新：允许覆盖仍在进行中的「加载更多」。
      slot.generation++;
      slot.appending = false;
      slot.nextPage = 1;
    } else {
      if (slot.loading || slot.appending) {
        return;
      }
      if (i != 0 || !slot.hasMore) {
        return;
      }
    }
    final gen = slot.generation;

    setState(() {
      if (refresh) {
        slot.loading = true;
        slot.error = null;
      } else {
        slot.appending = true;
      }
    });

    final pageNum = refresh ? 1 : slot.nextPage;
    final genreApi = _genreForApiRequest(i);

    try {
      final api = context.read<MovieProvider>().apiService;
      final page = await () async {
        if (refresh && pageNum == 1) {
          final mergeEnabled = context
              .read<SourceProvider>()
              .enabledSources
              .where((s) => s.enabled)
              .toList();
          if (mergeEnabled.length > 1) {
            return api.aggregateCategoryFirstPage(
              sources: mergeEnabled,
              category: widget.kind.categoryApiValue,
              region: _regionParam(),
              genre: genreApi,
            );
          }
        }
        return api.getMoviesByCategory(
          category: widget.kind.categoryApiValue,
          region: _regionParam(),
          genre: genreApi,
          page: pageNum,
        );
      }();
      if (!context.mounted || gen != slot.generation) {
        return;
      }
      setState(() {
        if (page.unsupported && refresh) {
          // 该源没有这个分类（例如站点没有「短剧」）：保持空列表 + 明确停到底，
          // 而不是回退成「全站最新」把电影塞进来。
          slot.movies = [];
          slot.nextPage = 1;
          slot.hasMore = false;
          slot.loading = false;
          slot.appending = false;
          slot.error = null;
          return;
        }
        if (refresh) {
          slot.movies = page.movies;
          slot.nextPage = page.hasMore ? 2 : 1;
          slot.loading = false;
        } else {
          slot.movies = _appendDedup(slot.movies, page.movies);
          slot.nextPage++;
          slot.appending = false;
        }
        // 空列表时不能再上报 hasMore，否则滚动会无限重复发请求。
        slot.hasMore = page.hasMore && slot.movies.isNotEmpty;
        slot.error = null;
      });
    } catch (e) {
      if (!context.mounted || gen != slot.generation) {
        return;
      }
      setState(() {
        if (refresh) {
          slot.loading = false;
        } else {
          slot.appending = false;
        }
        slot.error = e.toString();
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 480) {
      return;
    }
    final s0 = _slots[0];
    if (!s0.hasMore || s0.loading || s0.appending) {
      return;
    }
    unawaited(_fetchSlot(0, refresh: false));
  }

  List<Movie> _rankSlice(List<Movie> source) {
    if (source.isEmpty) {
      return const [];
    }
    final copy = List<Movie>.from(source);
    copy.sort((a, b) {
      final ra = a.rating.isFinite ? a.rating : 0;
      final rb = b.rating.isFinite ? b.rating : 0;
      return rb.compareTo(ra);
    });
    return copy.take(10).toList();
  }

  String _title(AppLocalizations l10n) {
    return switch (widget.kind) {
      ChannelPortalKind.movies => l10n.navChannelMovies,
      ChannelPortalKind.tv => l10n.navChannelTv,
      ChannelPortalKind.variety => l10n.navChannelVariety,
      ChannelPortalKind.anime => l10n.navChannelAnime,
      ChannelPortalKind.short => l10n.navChannelShort,
    };
  }

  /// 宽屏顶栏：与首页一致的品牌 + 当前频道名 + 频道导航 + 嵌入式搜索；窄屏仅标题。
  Widget _buildPortalAppBarTitle(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n, {
    required bool showDesktopShell,
  }) {
    if (!showDesktopShell) {
      return Text(_title(l10n));
    }
    final width = MediaQuery.sizeOf(context).width;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      children: [
                        TextSpan(
                          text: l10n.appTitle,
                          style:
                              const TextStyle(color: HiFiDesignTokens.accent),
                        ),
                        TextSpan(text: ' · ${_title(l10n)}'),
                      ],
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
                hintText: l10n.toolbarSearchPlaceholderInChannel(_title(l10n)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 模块「更多」：进入该模块对应的完整分类列表页（可继续无限刷新加载）。
  void _onModuleMore(int index) {
    final fixed = _fixedGenreForSlot(index);
    final genre = fixed ?? _filterGenre;
    AppRoutes.toCategoryList(
      context,
      category: widget.kind.categoryApiValue,
      genre: genre.isEmpty ? '全部' : genre,
      region: _filterRegion,
    );
  }

  /// 当前「类型 / 地区」筛选下该模块可见的影片。
  ///
  /// 采集站会忽略 `class` / `area` 参数（实测），所以除了在服务端按同族子类取数，
  /// 这里还要在已加载数据上补一层本地过滤，保证点筛选**立刻**有反馈。
  List<Movie> _visibleMovies(int i) {
    final all = _slots[i].movies;
    final genre = _filterGenre;
    final region = _filterRegion;
    final noGenre = genre.isEmpty || genre == '全部';
    final noRegion = region.isEmpty || region == '全部';
    if (noGenre && noRegion) return all;
    final knownRegions =
        CategoryFilterCatalog.regionsFor(widget.kind.categoryApiValue);
    return all
        .where(
          (m) =>
              CmsCategoryResolver.genreMatches(genre, m.genres) &&
              CmsCategoryResolver.regionMatches(
                region,
                m.region,
                knownRegions: knownRegions,
              ),
        )
        .toList(growable: false);
  }

  String _moduleTitle(AppLocalizations l10n, int i) {
    final fixed = _fixedGenreForSlot(i);
    if (fixed == null) {
      if (_filterGenre == '全部') {
        return l10n.categoryPortalModuleHighlights;
      }
      return l10n.categoryPortalModuleTagged(_filterGenre);
    }
    return l10n.categoryPortalModuleTagged(fixed);
  }

  Future<void> _onRefresh() async {
    await _loadAllModules();
    if (!context.mounted) {
      return;
    }
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  bool _showFooter() {
    return _slots[0].movies.isNotEmpty;
  }

  /// 单个模块（标题 + 栅格 + 右侧热播榜 + 更多按钮）。
  Widget _moduleSliver(int i, AppLocalizations l10n, bool wide) {
    final slot = _slots[i];
    final visible = _visibleMovies(i);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: CategoryPortalModuleRow(
          title: _moduleTitle(l10n, i),
          movies: visible,
          wide: wide,
          rankMovies: _rankSlice(visible),
          isLoading: slot.loading && visible.isEmpty && slot.error == null,
          errorMessage: slot.error,
          onMorePressed: () => _onModuleMore(i),
          moreTooltip: l10n.categoryPortalModuleMoreTooltip,
        ),
      ),
    );
  }

  List<Widget> _contentSlivers({
    required ThemeData theme,
    required AppLocalizations l10n,
    required bool wide,
  }) {
    return [
      for (var i = 0; i < 3; i++) _moduleSliver(i, l10n, wide),
      if (_showFooter())
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: _slots[0].appending
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _slots[0].hasMore
                      ? Text(
                          l10n.categoryPortalScrollForMore,
                          style: TextStyle(
                            color: theme.hintColor,
                            fontSize: 13,
                          ),
                        )
                      : Text(
                          l10n.homeEndOfListHint,
                          style: TextStyle(
                            color: theme.hintColor,
                            fontSize: 13,
                          ),
                        ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final wideTopBar = HiFiDesignTokens.useWideTopBarShell(context);

    return Scaffold(
      appBar: AppBar(
        title: _buildPortalAppBarTitle(
          context,
          theme,
          l10n,
          showDesktopShell: wideTopBar,
        ),
        actions: HiFiDesktopToolbar.trailingActions(
          context,
          includeSearchIcon: !wideTopBar,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: HiFiDesignTokens.shellMaxWidth,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 880;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CategoryGenreRegionFilterBand(
                      category: widget.kind.categoryApiValue,
                      selectedGenre: _filterGenre,
                      selectedRegion: _filterRegion,
                      onGenreSelected: (v) async {
                        if (v == _filterGenre || !context.mounted) {
                          return;
                        }
                        setState(() => _filterGenre = v);
                        await _loadAllModules();
                        if (!context.mounted) {
                          return;
                        }
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                      onRegionSelected: (v) async {
                        if (v == _filterRegion || !context.mounted) {
                          return;
                        }
                        setState(() => _filterRegion = v);
                        await _loadAllModules();
                        if (!context.mounted) {
                          return;
                        }
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                        child: RefreshIndicator(
                          onRefresh: _onRefresh,
                          child: CustomScrollView(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: _contentSlivers(
                              theme: theme,
                              l10n: l10n,
                              wide: wide,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

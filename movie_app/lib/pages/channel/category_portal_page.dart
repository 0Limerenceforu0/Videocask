import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/channel_portal_kind.dart';
import '../../config/routes.dart';
import '../../config/channel_portal_module_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../models/movie.dart';
import '../../providers/movie_provider.dart';
import '../../providers/source_provider.dart';
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

  Future<void> _fetchSlot(int i, {required bool refresh}) async {
    final slot = _slots[i];
    if (refresh) {
      if (slot.appending) {
        return;
      }
    } else {
      if (slot.loading || slot.appending) {
        return;
      }
      if (i != 0 || !slot.hasMore) {
        return;
      }
    }

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
      if (!context.mounted) {
        return;
      }
      setState(() {
        if (refresh) {
          slot.movies = page.movies;
          slot.nextPage = page.hasMore ? 2 : 1;
          slot.loading = false;
        } else {
          slot.movies = [...slot.movies, ...page.movies];
          slot.nextPage++;
          slot.appending = false;
        }
        slot.hasMore = page.hasMore;
        slot.error = null;
      });
    } catch (e) {
      if (!context.mounted) {
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

  void _onModuleMoreFromPortal() {
    final cat = widget.kind.homeBrowseCategoryName;
    if (cat != null) {
      AppRoutes.toHomeWithCategory(context, cat);
    } else {
      AppRoutes.toHome(context);
    }
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

  List<Widget> _contentSlivers({
    required ThemeData theme,
    required AppLocalizations l10n,
    required bool wide,
  }) {
    return [
      for (var i = 0; i < 3; i++)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: CategoryPortalModuleRow(
              title: _moduleTitle(l10n, i),
              movies: _slots[i].movies,
              wide: wide,
              rankMovies: _rankSlice(_slots[i].movies),
              isLoading: _slots[i].loading && _slots[i].movies.isEmpty,
              errorMessage: _slots[i].error,
              onMorePressed: _onModuleMoreFromPortal,
              moreTooltip: l10n.categoryPortalModuleMoreTooltip,
            ),
          ),
        ),
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

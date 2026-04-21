import 'dart:async' show Timer, unawaited;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/movie.dart';
import '../../models/torrent_info.dart';
import '../../providers/movie_provider.dart';
import '../../providers/source_provider.dart';
import '../../services/search_service.dart';
import '../../services/imdb_lookup_service.dart';
import '../../services/torrent_search_service.dart';
import '../../utils/torrent_title_display.dart';
import '../home/movie_card.dart';
import '../../config/routes.dart';
import '../../widgets/empty_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/hifi_design_tokens.dart';

/// 搜索页
class SearchPage extends StatefulWidget {
  /// 初始搜索关键词
  final String initialQuery;

  const SearchPage({
    super.key,
    this.initialQuery = '',
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  /// 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  /// 搜索服务（用于搜索历史和建议）
  final SearchService _searchService = SearchService();

  /// 焦点节点
  final FocusNode _focusNode = FocusNode();

  /// 搜索结果（本地状态，用于多源搜索的流式展示）
  List<Movie> _searchResults = [];

  /// 是否显示搜索建议
  bool _showSuggestions = false;

  /// 搜索建议
  List<String> _suggestions = [];

  /// 当前搜索关键词
  String _currentQuery = '';

  /// 热门搜索
  List<String> _hotKeywords = [];

  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 防抖定时器（用于搜索和搜索建议）
  Timer? _debounceTimer;

  /// 多源搜索状态文本
  String _multiSearchStatusText = '';

  /// 是否正在执行多源搜索
  bool _isMultiSourceSearching = false;

  /// 最近一次搜索因「没有任何已启用的搜索源」而未能发起（与「关键词无结果」区分）
  bool _searchBlockedNoSources = false;

  /// 磁力源搜索结果
  final TorrentSearchService _torrentSearchService = TorrentSearchService();
  List<TorrentInfo> _magnetResults = [];

  /// 是否正在搜索磁力源
  bool _isMagnetSearching = false;

  // ========== 折叠功能状态 ==========

  /// 是否展开其他源结果
  bool _isOtherSourcesExpanded = true;

  /// 是否展开磁力源结果
  bool _isMagnetSourcesExpanded = true;

  // ========== 筛选相关状态 ==========

  /// 类型筛选标签（空字符串表示"全部"）
  String _filterGenre = '';

  /// 排序方式（空字符串表示默认排序）
  String _filterSort = '';

  /// 可选的类型筛选列表
  static const List<String> _genreFilters = [
    '', // 全部
    '电影',
    '电视剧',
    '动漫',
    '综艺',
    '纪录片',
  ];

  /// 可选的排序方式列表
  static const List<MapEntry<String, String>> _sortOptions = [
    MapEntry('', '默认'),
    MapEntry('rating', '评分↓'),
    MapEntry('year_desc', '年份↓'),
    MapEntry('year_asc', '年份↑'),
  ];

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    _currentQuery = widget.initialQuery;

    if (widget.initialQuery.isNotEmpty) {
      _doSearch(widget.initialQuery);
    }

    _focusNode.addListener(_onFocusChange);
    _searchController.addListener(_onQueryChanged);
    _scrollController.addListener(_onScroll);

    _loadInitialData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 加载初始数据
  void _loadInitialData() {
    _hotKeywords = _searchService.hotKeywords.toList();
  }

  /// 焦点变化
  void _onFocusChange() {
    setState(() {
      _showSuggestions = _focusNode.hasFocus;
    });
  }

  /// 查询变化（带防抖）
  void _onQueryChanged() {
    final query = _searchController.text.trim();
    // 取消之前的防抖定时器
    _debounceTimer?.cancel();
    if (query.isNotEmpty && _focusNode.hasFocus) {
      // 防抖：用户停止输入 500ms 后才发起搜索建议请求
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _updateSuggestions(query);
      });
    } else {
      setState(() {
        _suggestions = [];
      });
    }
  }

  /// 更新搜索建议
  void _updateSuggestions(String query) async {
    final suggestions = await _searchService.getSuggestions(query);
    if (mounted) {
      setState(() {
        _suggestions = suggestions;
      });
    }
  }

  /// 滚动监听（多源搜索模式下不需要分页加载更多）
  void _onScroll() {
    // 多源搜索结果一次性展示，无需滚动加载更多
  }

  /// 执行搜索（带防抖）
  void _doSearch(String query) {
    if (query.trim().isEmpty) return;

    // 取消之前的防抖定时器
    _debounceTimer?.cancel();
    // 防抖：用户停止输入 500ms 后才发起搜索请求
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_performSearch(query));
    });
  }

  /// 实际执行搜索（多源并发搜索）
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _currentQuery = query;
      _searchResults = [];
      _magnetResults = [];
      _showSuggestions = false;
      _multiSearchStatusText = '正在搜索...';
      _searchBlockedNoSources = false;
      _filterGenre = '';
      _filterSort = '';
    });

    _focusNode.unfocus();

    // 添加搜索历史
    await _searchService.addSearchHistory(query);
    if (!mounted) return;

    final sourceProvider = context.read<SourceProvider>();
    final movieProvider = context.read<MovieProvider>();
    final enabledSources = sourceProvider.enabledSources;
    final hasMagnetSources = _torrentSearchService.activeConfigs().isNotEmpty;

    if (enabledSources.isEmpty && !hasMagnetSources) {
      if (mounted) {
        setState(() {
          _isMultiSourceSearching = false;
          _isMagnetSearching = false;
          _multiSearchStatusText = '';
          _searchBlockedNoSources = true;
        });
      }
      return;
    }

    if (hasMagnetSources) {
      setState(() => _isMagnetSearching = true);
      unawaited(
        _torrentSearchService
            .searchPreferringImdb(
          displayTitle: query.trim(),
          year: ImdbLookupService.yearFromUserQuery(query.trim()),
          strictMatchForDetailPage: false,
        )
            .then((list) {
          if (!mounted) return;
          setState(() {
            _magnetResults = list;
            _isMagnetSearching = false;
          });
        }),
      );
    } else {
      setState(() {
        _isMagnetSearching = false;
      });
    }

    if (enabledSources.isNotEmpty) {
      setState(() {
        _isMultiSourceSearching = true;
        _multiSearchStatusText = '正在搜索...';
      });
      unawaited(
        movieProvider.multiSourceSearch(
          query,
          sources: enabledSources,
        ),
      );
    } else {
      setState(() {
        _isMultiSourceSearching = false;
        _multiSearchStatusText = '';
      });
    }
  }

  /// 删除搜索历史
  void _deleteHistory(String keyword) async {
    await _searchService.deleteSearchHistory(keyword);
    if (mounted) {
      setState(() {});
    }
  }

  /// 清空搜索历史
  void _clearHistory() async {
    await _searchService.clearSearchHistory();
    if (mounted) {
      setState(() {});
    }
  }

  /// 获取筛选后的搜索结果
  ///
  /// 根据当前选中的类型和排序方式对原始搜索结果进行过滤和排序。
  List<Movie> get _filteredResults {
    var results = _searchResults;

    // 按类型筛选
    if (_filterGenre.isNotEmpty) {
      results = results.where((m) => m.genres.contains(_filterGenre)).toList();
    }

    // 按排序方式排序（创建副本，避免修改原始列表顺序）
    if (_filterSort == 'rating') {
      results = List.from(results)
        ..sort((a, b) => b.rating.compareTo(a.rating));
    } else if (_filterSort == 'year_desc') {
      results = List.from(results)..sort((a, b) => b.year.compareTo(a.year));
    } else if (_filterSort == 'year_asc') {
      results = List.from(results)..sort((a, b) => a.year.compareTo(b.year));
    }

    return results;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMultiSearchState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // 监听 MovieProvider 变化，实现多源搜索流式更新
    // 当 multiSourceSearch 内部调用 notifyListeners 时，
    // 这里会触发 rebuild，从而实现流式追加展示
    context.watch<MovieProvider>();

    final wide = HiFiDesignTokens.useWideTopBarShell(context);
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: HiFiDesignTokens.shellMaxWidth,
                    ),
                    child: _buildWideSearchChrome(context, theme, l10n),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: HiFiDesignTokens.shellMaxWidth,
                    ),
                    child: _buildBody(theme),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: _buildSearchField(theme),
        actions: [
          TextButton(
            onPressed: () => _doSearch(_searchController.text),
            child: const Text('搜索'),
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  /// 对齐 `hifi-screen-search-windows.html`：顶行返回 + 标题 + 设置；次行搜索框 + 主按钮。
  Widget _buildWideSearchChrome(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: backLabel,
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            Expanded(
              child: Text(
                l10n.toolbarSearch,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.toolbarSettings,
              onPressed: () => AppRoutes.toSettings(context),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildSearchField(theme)),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => _doSearch(_searchController.text),
              child: Text(l10n.toolbarSearch),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l10n.searchWideAggregateHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// 构建搜索框（B站风格：圆角12px，灰色背景，左侧搜索图标）
  Widget _buildSearchField(ThemeData theme) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _focusNode,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: '搜索影片、演员、导演...',
          hintStyle: TextStyle(
            color: theme.hintColor,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: theme.hintColor,
            size: 20,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults = [];
                      _magnetResults = [];
                      _suggestions = [];
                      _currentQuery = '';
                      _multiSearchStatusText = '';
                      _isMultiSourceSearching = false;
                      _isMagnetSearching = false;
                      _searchBlockedNoSources = false;
                      _filterGenre = '';
                      _filterSort = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (value) => _performSearch(value),
        onChanged: (value) {
          setState(() {});
        },
      ),
    );
  }

  /// 构建主体
  Widget _buildBody(ThemeData theme) {
    // 显示搜索建议
    if (_showSuggestions && _suggestions.isNotEmpty) {
      return _buildSuggestions(theme);
    }

    // 显示搜索结果
    if (_currentQuery.isNotEmpty) {
      return _buildSearchResults(theme);
    }

    // 显示搜索历史和热门搜索
    return _buildDefaultView(theme);
  }

  /// 从 MovieProvider 同步多源搜索状态到本地
  ///
  /// 在 build 方法中调用，确保每次 MovieProvider 状态变化时
  /// 本地状态也同步更新，实现流式追加效果。
  void _syncMultiSearchState() {
    final movieProvider = context.read<MovieProvider>();
    if (movieProvider.isMultiSourceSearching || _isMultiSourceSearching) {
      _searchResults = movieProvider.multiSearchResults;
      _isMultiSourceSearching = movieProvider.isMultiSourceSearching;
      _multiSearchStatusText = movieProvider.searchStatusText;
    }
  }

  /// 构建搜索建议（B站风格下拉列表）
  Widget _buildSuggestions(ThemeData theme) {
    return ListView.separated(
      itemCount: _suggestions.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: theme.dividerColor.withValues(alpha: 0.3),
        indent: 48,
      ),
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return InkWell(
          onTap: () {
            _searchController.text = suggestion;
            _doSearch(suggestion);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.search, color: theme.hintColor, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    suggestion,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                  ),
                ),
                Icon(Icons.arrow_upward, color: theme.hintColor, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建搜索结果（支持多源流式追加展示 + 筛选）
  Widget _buildSearchResults(ThemeData theme) {
    if (_searchBlockedNoSources) {
      return EmptyWidget(
        message: '没有已启用的影视搜索源，也未配置可用的磁力源。请在播放源管理中开启 CMS 源，或在设置中启用磁力搜索源。',
        icon: Icons.source_outlined,
        iconSize: 72,
        actionText: '去播放源管理',
        onAction: () => AppRoutes.toSourceManager(context),
      );
    }

    final anyMagnet = _magnetResults.isNotEmpty || _isMagnetSearching;
    final nothingYet = _searchResults.isEmpty && _magnetResults.isEmpty;
    final stillLoading = _isMultiSourceSearching || _isMagnetSearching;

    if (stillLoading && nothingYet) {
      return const LoadingWidget(message: '正在搜索影视与磁力...');
    }

    if (!stillLoading && nothingYet) {
      return NoSearchResultWidget(
        keyword: _currentQuery,
        onRetry: () => _performSearch(_currentQuery),
      );
    }

    final filteredResults = _filteredResults;
    final showMovieList = _searchResults.isNotEmpty;

    if (!showMovieList && anyMagnet) {
      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 16,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '磁力资源（${_magnetResults.length}）',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_isMagnetSearching) ...[
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isMagnetSourcesExpanded = !_isMagnetSourcesExpanded;
                      });
                    },
                    icon: Icon(
                      _isMagnetSourcesExpanded
                          ? Icons.expand_more
                          : Icons.expand_less,
                      size: 20,
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
              if (_isMagnetSourcesExpanded) ...[
                const SizedBox(height: 8),
                if (_isMagnetSearching && _magnetResults.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '正在从已启用的磁力源聚合结果…',
                      style: TextStyle(color: theme.hintColor, fontSize: 13),
                    ),
                  ),
                ..._magnetResults.map((t) => _buildMagnetSearchTile(theme, t)),
              ],
            ],
          ),
        ),
      );
    }

    // 磁力区块 + 影视列表不能放在同一个 Column 里：磁力条目多时总高度会超过一屏，
    // 在非 Expanded 的子节点上会直接触发 BOTTOM OVERFLOWED。统一放进可滚动视图。
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 其他源结果（放在前面）
        if (showMovieList) ...[
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 16,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '影视资源（${_searchResults.length}）',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_isMultiSourceSearching) ...[
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isOtherSourcesExpanded = !_isOtherSourcesExpanded;
                      });
                    },
                    icon: Icon(
                      _isOtherSourcesExpanded
                          ? Icons.expand_more
                          : Icons.expand_less,
                      size: 20,
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isOtherSourcesExpanded) ...[
            SliverToBoxAdapter(child: _buildFilterBar(theme)),
            if (!_isMultiSourceSearching && filteredResults.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '没有符合筛选条件的结果',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _filterGenre = '';
                              _filterSort = '';
                            });
                          },
                          child: const Text('清除筛选'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= filteredResults.length) {
                        return _buildSearchProgress(theme);
                      }
                      return MovieCardHorizontal(movie: filteredResults[index]);
                    },
                    childCount: filteredResults.length +
                        ((_isMultiSourceSearching ||
                                _multiSearchStatusText.isNotEmpty)
                            ? 1
                            : 0),
                  ),
                ),
              ),
          ],
        ],
        // 磁力资源（放在后面）
        if (anyMagnet)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 3,
                            height: 16,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '磁力资源（${_magnetResults.length}）',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_isMagnetSearching) ...[
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isMagnetSourcesExpanded =
                                !_isMagnetSourcesExpanded;
                          });
                        },
                        icon: Icon(
                          _isMagnetSourcesExpanded
                              ? Icons.expand_more
                              : Icons.expand_less,
                          size: 20,
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                  if (_isMagnetSourcesExpanded) ...[
                    const SizedBox(height: 8),
                    if (_isMagnetSearching && _magnetResults.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '正在从已启用的磁力源聚合结果…',
                          style:
                              TextStyle(color: theme.hintColor, fontSize: 13),
                        ),
                      ),
                    ..._magnetResults
                        .map((t) => _buildMagnetSearchTile(theme, t)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMagnetSearchTile(ThemeData theme, TorrentInfo t) {
    final lines = splitTorrentDisplayTitle(t.name);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.link, color: theme.colorScheme.primary, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lines.primary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (lines.secondary != null &&
                          lines.secondary!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          lines.secondary!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _magnetMetaChip(
                  theme,
                  Icons.storage_outlined,
                  '体积 ${t.sizeFormatted}',
                ),
                _magnetMetaChip(
                  theme,
                  Icons.cloud_outlined,
                  '索引 ${t.source}',
                ),
                _magnetMetaChip(
                  theme,
                  Icons.arrow_upward,
                  '做种 ${t.seedersFormatted}',
                  valueColor: const Color(0xFF2E7D32),
                ),
                _magnetMetaChip(
                  theme,
                  Icons.arrow_downward,
                  '下载 ${t.leechers}',
                ),
                if (t.imdbId != null && t.imdbId!.isNotEmpty)
                  _magnetMetaChip(
                    theme,
                    Icons.movie_outlined,
                    'IMDb ${t.imdbId}',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => AppRoutes.toMagnetTorrentDetail(context, t),
                  icon: const Icon(Icons.play_arrow, size: 22),
                  label: const Text('播放'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => AppRoutes.toMagnetTorrentDetail(context, t),
                  child: const Text('进入详情'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _magnetMetaChip(
    ThemeData theme,
    IconData icon,
    String text, {
    Color? valueColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: valueColor ?? theme.hintColor),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: valueColor ?? theme.hintColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// 构建筛选栏（类型标签 + 排序按钮）
  Widget _buildFilterBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：类型筛选标签
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _genreFilters.map((genre) {
                final isSelected = _filterGenre == genre;
                final label = genre.isEmpty ? '全部' : genre;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _filterGenre = genre;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.textTheme.bodySmall?.color,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // 第二行：排序选项
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _sortOptions.map((entry) {
                final isSelected = _filterSort == entry.key;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      // 再次点击已选中的排序方式时取消排序
                      _filterSort = isSelected ? '' : entry.key;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.secondaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.secondary
                            : theme.dividerColor,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected)
                          Icon(
                            Icons.sort,
                            size: 14,
                            color: theme.colorScheme.onSecondaryContainer,
                          )
                        else
                          const SizedBox(width: 14),
                        const SizedBox(width: 2),
                        Text(
                          entry.value,
                          style: TextStyle(
                            color: isSelected
                                ? theme.colorScheme.onSecondaryContainer
                                : theme.textTheme.bodySmall?.color,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建搜索进度提示
  ///
  /// 显示在搜索结果列表底部，提示用户搜索进度。
  /// 搜索中显示加载动画，搜索完成后显示最终统计。
  Widget _buildSearchProgress(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 搜索中显示加载动画
            if (_isMultiSourceSearching)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (_isMultiSourceSearching) const SizedBox(width: 8),
            // 搜索状态文本
            Text(
              _multiSearchStatusText,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建默认视图（搜索历史 + 热门搜索）
  Widget _buildDefaultView(ThemeData theme) {
    // 按时间分组搜索历史
    final historyWithTime = _searchService.searchHistoryWithTime;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayKeywords = <String>[];
    final yesterdayKeywords = <String>[];
    final earlierKeywords = <String>[];

    for (final entry in historyWithTime) {
      final keyword = entry['keyword'] as String;
      final timeStr = entry['time'] as String?;
      DateTime? searchTime;
      if (timeStr != null) {
        searchTime = DateTime.tryParse(timeStr);
      }
      searchTime ??= now;

      final searchDate =
          DateTime(searchTime.year, searchTime.month, searchTime.day);
      if (searchDate == today || searchDate.isAfter(today)) {
        todayKeywords.add(keyword);
      } else if (searchDate == yesterday ||
          (searchDate.isAfter(yesterday) && searchDate.isBefore(today))) {
        yesterdayKeywords.add(keyword);
      } else {
        earlierKeywords.add(keyword);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 搜索历史（按时间分组）
          if (historyWithTime.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // B站风格左侧装饰条
                    Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '最近搜索',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: _clearHistory,
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: theme.hintColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '清空',
                        style: TextStyle(
                          color: theme.hintColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 今天
            if (todayKeywords.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '今天',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: todayKeywords.map((keyword) {
                  return _buildHistoryChip(theme, keyword);
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // 昨天
            if (yesterdayKeywords.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '昨天',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: yesterdayKeywords.map((keyword) {
                  return _buildHistoryChip(theme, keyword);
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // 更早
            if (earlierKeywords.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '更早',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: earlierKeywords.map((keyword) {
                  return _buildHistoryChip(theme, keyword);
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
          ],

          // 热门搜索（B站风格标题）
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '热门搜索',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hotKeywords.asMap().entries.map((entry) {
              final index = entry.key;
              final keyword = entry.value;
              return _buildHotChip(theme, keyword, index);
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 构建历史标签（B站风格圆角胶囊样式）
  Widget _buildHistoryChip(ThemeData theme, String keyword) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              _searchController.text = keyword;
              _doSearch(keyword);
            },
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history,
                    size: 14,
                    color: theme.hintColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    keyword,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 桌面端长按不可靠：提供可见删除按钮
          InkWell(
            onTap: () => _deleteHistory(keyword),
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
              child: Icon(
                Icons.close,
                size: 16,
                color: theme.hintColor.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建热门搜索标签（B站风格）
  Widget _buildHotChip(ThemeData theme, String keyword, int index) {
    final isTopThree = index < 3;

    return GestureDetector(
      onTap: () {
        _searchController.text = keyword;
        _doSearch(keyword);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isTopThree
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: isTopThree
              ? Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                )
              : Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                  width: 1,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                color: isTopThree ? theme.colorScheme.primary : theme.hintColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              keyword,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: isTopThree ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

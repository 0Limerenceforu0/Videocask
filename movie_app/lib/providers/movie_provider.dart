import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/category_filter_catalog.dart';
import '../models/movie.dart';
import '../models/play_source.dart';
import '../services/api_service.dart';
import '../services/cms_category_resolver.dart';
import '../services/category_filter_options.dart';
import '../services/banner_picker.dart';
import '../services/detail_source_matcher.dart';
import '../utils/movie_dedupe.dart';

/// 影片数据状态管理
class MovieProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  /// 暴露 API 服务实例（用于读取源切换提示等信息）
  ApiService get apiService => _api;

  /// 个性化推荐结果缓存
  List<Movie> _personalizedRecommendations = [];

  /// 个性化推荐结果
  List<Movie> get personalizedRecommendations => _personalizedRecommendations;

  /// 首页数据
  List<Movie> _bannerList = [];
  List<Movie> _homeMovies = []; // 统一的首页影片列表（用于无限滚动）
  List<Movie> _hotMovies = [];
  List<Movie> _latestMovies = [];
  List<Movie> _topRatedMovies = [];
  List<Movie> _classicMovies = [];

  /// 分区独立错误状态
  String _bannerError = '';
  String _hotError = '';
  String _latestError = '';
  String _topRatedError = '';
  String _classicError = '';

  /// 分区独立加载状态
  final bool _isBannerLoading = false;
  final bool _isHotLoading = false;
  final bool _isLatestLoading = false;
  final bool _isTopRatedLoading = false;
  final bool _isClassicLoading = false;

  /// 分区独立错误状态 getter
  String get bannerError => _bannerError;
  String get hotError => _hotError;
  String get latestError => _latestError;
  String get topRatedError => _topRatedError;
  String get classicError => _classicError;

  /// 分区独立加载状态 getter
  bool get isBannerLoading => _isBannerLoading;
  bool get isHotLoading => _isHotLoading;
  bool get isLatestLoading => _isLatestLoading;
  bool get isTopRatedLoading => _isTopRatedLoading;
  bool get isClassicLoading => _isClassicLoading;

  /// 首页分页状态
  int _homePage = 1; // 当前页码
  bool _hasMoreHome = true; // 是否还有更多数据
  bool _isLoadingMore = false; // 是否正在加载更多

  /// 当前影片详情
  Movie? _currentMovie;

  /// 详情加载会话序号：每次 [loadMovieDetail] 绑定一个由详情页传入的 session，
  /// 详情页据此认领「属于自己的」currentMovie——既防跨页/跨源串片，
  /// 又允许自动换源后身份（id/sourceId）变化仍被本页正常采纳。
  int _detailSession = 0;

  /// 从 CMS 详情 push 磁力详情前保存，pop 时恢复（避免底层详情被全局状态污染）。
  _DetailReturnSnapshot? _detailReturnSnapshot;

  /// 分类影片原始列表（服务端返回，未做类型/地区过滤）
  List<Movie> _categoryMovies = [];

  /// 应用「类型 / 地区」本地过滤后的展示列表（缓存，避免每帧重算）
  List<Movie> _categoryVisibleMovies = [];

  /// 分类页当前类型筛选（如「动作」「家庭」）
  String _categoryGenreFilter = '全部';

  /// 分类页当前地区筛选
  String _categoryRegionFilter = '全部';

  /// 当前播放源完全没有这个分类（例如站点没有「短剧」）
  bool _categoryUnsupported = false;

  /// 是否正在加载（首页等，勿与详情加载混用）
  bool _isLoading = false;

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 详情页专用，避免与 [loadHomeData] 共享 [_isLoading] 产生竞态（首页先结束会把详情误判为失败）
  bool _isLoadingDetail = false;

  /// 是否正在加载影片详情
  bool get isLoadingDetail => _isLoadingDetail;

  int get detailSession => _detailSession;

  /// 错误信息
  String _errorMessage = '';

  /// 错误信息
  String get errorMessage => _errorMessage;

  /// 当前分类页码
  int _categoryPage = 1;

  /// 是否有更多分类数据
  bool _hasMoreCategory = true;

  /// 当前分类
  String _currentCategory = '';

  /// 当前选中的「小分类」type_id（首页子类 chip）。
  ///
  /// null = 精选模式（首屏只拉前 [ApiService.defaultSubClassCount] 个子类，
  /// 见 `loadCategoryMovies`）；非空 = 只拉该子类；配合 [_subClassAll]。
  /// 续页（`refresh: false`）必须沿用同一选择，否则翻页会换一批子类取数。
  int? _selectedSubClassId;

  /// 是否展开「全部」子类（用户显式点「全部」chip，接受全量请求代价）。
  bool _subClassAll = false;

  /// 类目 Tab 首屏缓存（2026-10-21）：key = 类目|源id集合|子类模式。
  ///
  /// 切 Tab 首屏要并发拉「全部源 × 3 子类」（≈15 个 1MB 请求）且曾经
  /// **无缓存**——切走再切回同一个 Tab 重新全量拉，用户感知「点 Tab 很慢」。
  /// 命中缓存时同步渲染旧数据 + 后台静默刷新，切回秒开。
  final Map<String, CmsListPage> _categoryFirstPageCache = {};

  /// 首屏缓存最大条数（类目有限，10 个足够覆盖全部 Tab + 小分类切换）。
  static const int _categoryFirstPageCacheLimit = 10;

  /// 类目加载代次：每次 refresh ++；请求回来时比对，过期结果丢弃。
  ///
  /// 防「缓存秒出 → 用户立刻滚动续页 → 首屏后台刷新才回来」把续页追加的
  /// 数据用旧首屏覆盖（列表瞬间倒退）。
  int _categoryLoadGeneration = 0;

  /// 后台预取的下一页（主源）：首屏渲染完就拉，滚动续页时瞬时命中，
  /// 用户感知「往下滑立刻有内容」。
  _CategoryPrefetchedPage? _categoryPrefetched;

  /// 首屏补充源上限：其余启用源**只补首屏**且限量（2026-10-21）。
  ///
  /// 用户源多时（几十上百）全量并发会让请求数与流量失控；主轴是「使用中」的
  /// 主源，补充源只取前 N 个，补不到也不影响可用（主源内容已在）。
  static const int categorySupplementMaxSources = 5;

  /// 「名称|年份」去重键，与 [_appendCategoryDedup] 同一口径
  /// （统一走 [MovieDedupe]，避免与 ApiService 聚合层口径漂移）。
  static String _movieDedupeKey(Movie m) => MovieDedupe.key(m);

  /// 生成类目首屏缓存 key：类目 + 主源 + 源集合 + 子类模式。
  ///
  /// 主源与源集合任一变化（用户在设置里切「使用中」或开关源）都必须换 key，
  /// 否则会用旧组合的数据渲染。
  String _categoryFirstPageCacheKey(
    String category,
    List<PlaySource> sources, {
    PlaySource? primary,
    int? subClassId,
    bool subClassAll = false,
  }) {
    final ids = sources.map((s) => s.id).join(',');
    final mode = subClassId != null
        ? 'sub:$subClassId'
        : (subClassAll ? 'all' : 'featured');
    return '$category|${primary?.id ?? ''}|$ids|$mode';
  }

  // ===== 多源搜索状态 =====

  /// 是否正在执行多源搜索
  bool _isMultiSourceSearching = false;

  /// 多源搜索是否正在进行中
  bool get isMultiSourceSearching => _isMultiSourceSearching;

  /// 搜索状态文本（如："已搜索 2/4 个源，共找到 28 部"）
  String _searchStatusText = '';

  /// 搜索状态文本
  String get searchStatusText => _searchStatusText;

  /// 多源搜索结果列表
  List<Movie> _multiSearchResults = [];

  /// 多源搜索结果列表
  List<Movie> get multiSearchResults => _multiSearchResults;

  /// 当前这轮多源搜索的关键词。
  ///
  /// 2026-10-22：搜索页是**从本 provider 镜像**聚合结果的，而 provider 是
  /// app 级全局单例（首页也共用）。没有关键词标记时，首页的 `notifyListeners`
  /// 会把上一轮/其它页面的结果覆写进搜索页 —— 这是「页面来回跳」的一个来源。
  /// 搜索页只接受「关键词 == 自己当前关键词」的那一轮结果。
  String _multiSearchKeyword = '';

  /// 当前这轮多源搜索的关键词
  String get multiSearchKeyword => _multiSearchKeyword;

  /// 多源搜索代次：每次 [multiSourceSearch] 自增。
  ///
  /// 旧一轮的流若晚于新一轮落地，会把新结果覆盖、也会提前关掉新一轮的
  /// loading 标志 → 表现为「先有结果、再转加载、再转无结果」的乱跳。
  /// 回调时比对代次，过期的一轮直接丢弃。
  int _multiSearchGeneration = 0;

  // Getter
  List<Movie> get bannerList => _bannerList;
  List<Movie> get homeMovies => _homeMovies;
  List<Movie> get hotMovies => _hotMovies;
  List<Movie> get latestMovies => _latestMovies;
  List<Movie> get topRatedMovies => _topRatedMovies;
  List<Movie> get classicMovies => _classicMovies;
  Movie? get currentMovie => _currentMovie;

  /// 分类展示列表（已按类型/地区过滤）
  List<Movie> get categoryMovies => _categoryVisibleMovies;
  bool get hasMoreCategory => _hasMoreCategory;
  String get currentCategory => _currentCategory;
  String get categoryGenreFilter => _categoryGenreFilter;
  String get categoryRegionFilter => _categoryRegionFilter;
  bool get categoryUnsupported => _categoryUnsupported;

  /// 已加载的分类列表里是否存在**带类型/地区元数据**的条目。
  ///
  /// 采集源的列表接口普遍不返回 `vod_class` / `vod_area`（2026-10-21 实测
  /// lzi / ffzy 的 `ac=list` 只有 8 个字段，加 `h` 参数也无效）。全都没有时，
  /// 类型/地区筛选在客户端无法生效 —— UI 应如实告知，而不是让用户以为「只有几条」。
  bool get categoryHasFilterMetadata {
    for (final m in _categoryMovies) {
      if (m.genreTags.isNotEmpty || m.region.trim().isNotEmpty) return true;
    }
    return false;
  }

  /// 分类页的**动态**筛选候选词（从已加载条目的真实 `vod_class`/`vod_area` 聚合）。
  ///
  /// 静态词表（`CategoryFilterCatalog`）与源站实际标注对不上 —— 词表写「热血/
  /// 校园/百合」，而站点只标到「动画/动作/奇幻」这一层，选「热血」必然 0 命中。
  /// 改用源里真实存在的词，用户选到的每个词都必然有结果。
  CategoryFilterOptions get categoryFilterOptions =>
      aggregateFilterOptions(_categoryMovies);

  /// 当前类目实际可用的筛选词（动态优先，缺失时回退静态词表）。
  ///
  /// 动态词表非空时取「动态 ∪ 静态里源也有的」，避免翻页后用户已选的词突然消失。
  List<String> get categoryGenreOptions {
    final dynamic = categoryFilterOptions.genres;
    final staticOptions = CategoryFilterCatalog.genresFor(_currentCategory);
    if (dynamic.isEmpty) return staticOptions;
    final merged = <String>[...dynamic];
    for (final g in staticOptions) {
      if (g == '全部') continue;
      if (merged.contains(g)) continue;
      // 只有源里真的出现过这个词才补进来，否则等于给用户一个必然 0 命中的选项。
      if (dynamic.contains(g)) merged.add(g);
    }
    return ['全部', ...merged];
  }

  /// 当前类目实际可用的地区候选词（规则同上）。
  List<String> get categoryRegionOptions {
    final dynamic = categoryFilterOptions.regions;
    final staticOptions = CategoryFilterCatalog.regionsFor(_currentCategory);
    if (dynamic.isEmpty) return staticOptions;
    final merged = <String>[...dynamic];
    for (final r in staticOptions) {
      if (r == '全部') continue;
      if (merged.contains(r)) continue;
      if (dynamic.contains(r)) merged.add(r);
    }
    return ['全部', ...merged];
  }

  /// 把已选的类型/地区归一到**当前实际可用**的词表。
  ///
  /// 动态词表会随已加载数据变化（翻页后可能出现新词、也可能某个词不再出现）。
  /// 若用户已选的词不在当前词表里，chip 会变成「悬空选中」状态 —— 必须回退到
  /// 「全部」，否则筛选条件与 UI 显示不一致。
  ({String genre, String region}) normalizeSelectedFilters({
    required String genre,
    required String region,
  }) {
    final genreOptions = categoryGenreOptions;
    final regionOptions = categoryRegionOptions;
    return (
      genre: genreOptions.contains(genre) ? genre : '全部',
      region: regionOptions.contains(region) ? region : '全部',
    );
  }

  /// 应用「类型 / 地区」本地过滤。
  ///
  /// 采集站的 `ac=detail` 只认 `t`（type_id），`class` / `area` 参数会被直接忽略
  /// （2026-09-29 实测），所以筛选只能在客户端做——好处是点击立刻生效。
  void _applyCategoryFilter() {
    final genre = _categoryGenreFilter;
    final region = _categoryRegionFilter;
    if ((genre == '全部' || genre.isEmpty) &&
        (region == '全部' || region.isEmpty)) {
      _categoryVisibleMovies = _categoryMovies;
      return;
    }
    final knownRegions = CategoryFilterCatalog.regionsFor(_currentCategory);
    _categoryVisibleMovies = _categoryMovies
        .where(
          (m) =>
              CmsCategoryResolver.genreMatches(genre, m.genreTags) &&
              CmsCategoryResolver.regionMatches(
                region,
                m.region,
                knownRegions: knownRegions,
              ),
        )
        .toList(growable: false);
  }

  /// 切换分类页的「类型 / 地区」筛选（本地过滤，不发请求，点击立即生效）。
  void setCategoryFilter({String? genre, String? region}) {
    final nextGenre = genre ?? _categoryGenreFilter;
    final nextRegion = region ?? _categoryRegionFilter;
    if (nextGenre == _categoryGenreFilter &&
        nextRegion == _categoryRegionFilter) {
      return;
    }
    _categoryGenreFilter = nextGenre;
    _categoryRegionFilter = nextRegion;
    _applyCategoryFilter();
    notifyListeners();
  }

  /// 追加分页数据时按「名称 + 年份」去重，避免同一部片被反复塞进列表。
  static List<Movie> _appendCategoryDedup(List<Movie> base, List<Movie> more) {
    if (more.isEmpty) return base;
    final seen = <String>{for (final m in base) MovieDedupe.key(m)};
    final out = List<Movie>.from(base);
    for (final m in more) {
      if (seen.add(MovieDedupe.key(m))) out.add(m);
    }
    return out;
  }

  /// 首页是否还有更多数据
  bool get hasMoreHome => _hasMoreHome;

  /// 首页是否正在加载更多
  bool get isLoadingMore => _isLoadingMore;

  /// 首页分区自身的加载标志。
  ///
  /// 之前复用 [_isLoading]，而 `loadCategoryMovies` 也会写它 —— 首页与分类两条
  /// 链路并发时互相覆盖，导致补跑判定失真、快速连点 Tab 后 banner 停在旧类目。
  /// 故独立出来，只服务首页链路。
  bool _isHomeLoading = false;

  /// 分类 Tab 首屏（refresh）加载中标志。
  ///
  /// [loadHomeData] 与 [loadCategoryMovies] 共用 `_isLoading` 表达「首屏转圈」，
  /// 两条链路可能并发（用户快速连点 Tab）。分类在跑时，首页的 finally 不能
  /// 清 `_isLoading`，否则分类的转圈会被提前灭掉、首屏内容还没出来就停转。
  bool _isCategoryFirstPageLoading = false;

  /// 初始化
  Future<void> init() async {
    await _api.init();
  }

  /// 加载首页数据（**推荐 Tab 专用**，分区独立加载互不影响）。
  ///
  /// 类目 Tab 不要用这个方法 —— 它是全站取数（每个分类各 5 页，见
  /// `ApiService.getHomeData` 注释）。类目 Tab 应「拉分类列表 → 派生分区」
  /// （`deriveHomeSectionsFromCategory`），零额外请求。
  Future<void> loadHomeData() async {
    if (_isHomeLoading) return;
    _isHomeLoading = true;
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final homeData = await _api.getHomeData();

      // 分区独立加载：每个分区的成功/失败互不影响
      // 轮播
      if (homeData.bannerList.isNotEmpty) {
        _bannerList = homeData.bannerList;
        _bannerError = '';
      } else {
        _bannerError = '轮播数据为空';
      }

      // 热门影视
      if (homeData.hotMovies.isNotEmpty) {
        _hotMovies = homeData.hotMovies;
        _hotError = '';
      } else {
        _hotError = '热门影视数据为空';
      }

      // 最近更新
      if (homeData.latestMovies.isNotEmpty) {
        _latestMovies = homeData.latestMovies;
        _latestError = '';
      } else {
        _latestError = '最近更新数据为空';
      }

      // 高分推荐
      if (homeData.topRatedMovies.isNotEmpty) {
        _topRatedMovies = homeData.topRatedMovies;
        _topRatedError = '';
      } else {
        _topRatedError = '高分推荐数据为空';
      }

      // 经典影片
      if (homeData.classicMovies.isNotEmpty) {
        _classicMovies = homeData.classicMovies;
        _classicError = '';
      } else {
        _classicError = '经典影片数据为空';
      }

      // 统一列表使用热门推荐数据作为首页初始数据
      _homeMovies = List<Movie>.from(homeData.hotMovies);
      _hasMoreHome = _homeMovies.isNotEmpty;
      _homePage = 6; // 首次已并发加载5页，下一页从第6页开始
    } catch (e) {
      _errorMessage = '加载首页数据失败: $e';
      // 分区独立错误
      _bannerError = '加载失败';
      _hotError = '加载失败';
      _latestError = '加载失败';
      _topRatedError = '加载失败';
      _classicError = '加载失败';
    } finally {
      _isHomeLoading = false;
      // 与分类首屏共用 _isLoading：分类加载在跑时不清零，避免踩掉它的转圈；
      // 没有并发分类加载时必须清零 —— 之前这里只判 notify 不清标志，导致
      // _isLoading 永真、且完成时因 `if (!_isLoading)` 守卫写反而不发通知：
      // 首页骨架屏卡死（数据早已落到 provider，UI 收不到重建信号，直到
      // 滚动/下拉触发别的 notify 才「突然出现」——即用户报的一直转圈）。
      if (!_isCategoryFirstPageLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  /// 重试加载单个分区（重新调用 loadHomeData，分区独立错误会被清除）
  Future<void> retryHomeSection(String section) async {
    _errorMessage = '';
    switch (section) {
      case 'banner':
        _bannerError = '';
        break;
      case 'hot':
        _hotError = '';
        break;
      case 'latest':
        _latestError = '';
        break;
      case 'topRated':
        _topRatedError = '';
        break;
      case 'classic':
        _classicError = '';
        break;
    }
    notifyListeners();
    await loadHomeData();
  }

  /// 从**已加载的分类列表**派生首页分区数据（轮播/最近/热门/高分）。
  ///
  /// 类目 Tab 下不要再单独调 `getHomeData(category:)` —— 那是「每个子类各拉 5 页」
  /// （上限 12 子类 × 5 页 = 60 个请求），而分类列表本身已经拉过同样的数据，
  /// 两边叠加会让单次切 Tab 打出上百个请求（实测 343 个），既慢又极易被采集站限流。
  ///
  /// 这里直接复用分类列表：零额外请求，且轮播/分区与网格内容天然一致。
  void deriveHomeSectionsFromCategory() {
    final movies = _categoryMovies;
    if (movies.isEmpty) {
      _bannerList = [];
      _hotMovies = [];
      _latestMovies = [];
      _topRatedMovies = [];
      _classicMovies = [];
      notifyListeners();
      return;
    }
    final sorted = List<Movie>.from(movies)
      ..sort((a, b) {
        final c = b.rating.compareTo(a.rating);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    // 轮播只从「属于该类目」的条目里挑：多源合并会混进异类（实测 lzi
    // 「海外动漫」里有印度真人剧），不滤的话异类按评分霸占 banner，
    // 表现为「动漫 Tab 顶部放着剧集简介」。全滤掉时 pickBannerMovies
    // 自行退回全量，不会让轮播消失。
    _bannerList = pickBannerMovies(sorted, category: _currentCategory);
    _latestMovies = List<Movie>.from(movies);
    _hotMovies = List<Movie>.from(movies);
    _topRatedMovies = sorted.length > 30 ? sorted.sublist(0, 30) : sorted;
    _classicMovies = List<Movie>.from(movies);
    _bannerError = '';
    _hotError = '';
    _latestError = '';
    _topRatedError = '';
    _classicError = '';
    // ⚠️ 必须通知：否则轮播/分区仍是旧值，UI 显示的是上一个类目的内容
    // （表现为「切到动漫，banner 却是欧美剧」）。
    notifyListeners();
  }

  /// 加载更多首页数据（无限滚动）。
  ///
  /// 类目 Tab 下走**分类列表的续页**（`loadCategoryMovies(refresh: false)`），
  /// 不另起一套 `_homePage` —— 否则同一批数据会有两套翻页状态，
  /// 容易出现「网格到底了但分区还在转圈」这类不一致。
  Future<void> loadMoreHome() async {
    if (_isLoadingMore || !_hasMoreHome) return;

    // 类目 Tab：复用分类翻页。
    if (_currentCategory.isNotEmpty) {
      // 「全部」是 UI 占位值，不能原样发给服务端（area/genre 参数），
      // 与 home_page 的 _categoryRegionParam/_categoryGenreParam 同口径归一。
      final region = _categoryRegionFilter == '全部' ? '' : _categoryRegionFilter;
      final genre = _categoryGenreFilter == '全部' ? '' : _categoryGenreFilter;
      await loadCategoryMovies(
        category: _currentCategory,
        region: region,
        genre: genre,
        refresh: false,
      );
      deriveHomeSectionsFromCategory();
      return;
    }
    _isLoadingMore = true;
    notifyListeners();

    try {
      final page = await _api.fetchMoviesByPage(_homePage);
      if (page.movies.isEmpty) {
        _hasMoreHome = false;
      } else {
        _homeMovies.addAll(page.movies);
        _homePage++;
        _hasMoreHome = page.hasMore;
      }
    } catch (e) {
      debugPrint('加载更多首页数据失败: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// 进入详情页首帧前调用：立即进入加载态，避免首帧误判为「加载失败」。
  ///
  /// 与 [loadMovieDetail] 开头逻辑一致；在 Widget [initState] 同步调用后，
  /// 配合页面 `context.watch<MovieProvider>()` 可正确显示骨架屏。
  void primeDetailLoad(String movieId) {
    _isLoadingDetail = true;
    _errorMessage = '';
    if (_currentMovie?.id != movieId) {
      _currentMovie = null;
    }
    notifyListeners();
  }

  /// 加载影片详情
  Future<void> loadMovieDetail(
    String movieId, {
    String? titleHint,
    String? yearHint,
    int session = 0,
  }) async {
    primeDetailLoad(movieId);

    try {
      final movie = await _api.getMovieDetail(
        movieId,
        titleHint: titleHint,
        yearHint: yearHint,
      );
      // 绑定本次加载会话：详情页按 _detailSession == _expectedDetailSession
      // 认领，防串片且允许自动换源后身份变化仍被本页采纳。
      _detailSession = session;
      _currentMovie = movie;
      if (_currentMovie == null) {
        _errorMessage = '未获取到该影片（可能已下架、ID 无效或当前源无数据），请换源或返回重试。';
      }
    } catch (e) {
      _errorMessage = '加载影片详情失败: $e';
    } finally {
      _isLoadingDetail = false;
      notifyListeners();
    }
  }

  /// 加载分类影片
  ///
  /// 分类模式与首页推荐分离：结果写入 [categoryMovies]；不再覆盖 [homeMovies]，
  /// 便于从分类返回「推荐」时保持原首页数据。
  ///
  /// **最小代价取数（2026-10-21）**：切 Tab 首屏默认只拉前
  /// [ApiService.defaultSubClassCount] 个子类（实测全展开 = 12 子类 × N 源
  /// ≈ 60 个 961KB 请求；收到 3 个约 2s 出内容）。用户在首页点「小分类」chip
  /// 时传 [subClassId] 只拉该子类，或 [subClassAll] 显式展开全部。
  /// 续页（`refresh: false`）自动沿用当前选择，翻页不会换子类取数。
  Future<void> loadCategoryMovies({
    required String category,
    String region = '',
    String year = '',
    String sort = '',
    String genre = '',
    bool refresh = false,
    int? subClassId,
    bool subClassAll = false,
    List<PlaySource>? mergeSources,
  }) async {
    if (refresh) {
      _categoryPage = 1;
      _categoryMovies = [];
      _categoryVisibleMovies = [];
      _categoryUnsupported = false;
      _hasMoreCategory = true;
      // 服务端只认 type_id，筛选条件落到本地过滤状态。
      _categoryGenreFilter = genre.isEmpty ? '全部' : genre;
      _categoryRegionFilter = region.isEmpty ? '全部' : region;
      _selectedSubClassId = subClassId;
      _subClassAll = subClassAll;
      _categoryLoadGeneration++;
      // 丢弃上一类目的预取页：页码/代次都换了，不能给新首屏续页消费。
      _categoryPrefetched = null;
    }

    if (!_hasMoreCategory) return;

    _currentCategory = category;
    final generation = _categoryLoadGeneration;
    final enabled =
        mergeSources?.where((s) => s.enabled).toList() ?? const <PlaySource>[];

    // 翻页主轴 = 设置里「使用中」的主源（_api.currentSource）；无主源时
    // 回退第一个启用源。其余源仅做首屏补充，不参与翻页 —— 源动辄几十上百
    // 个，全源并发 × 3 子类的请求/数据量不可接受，且首屏要等最慢的源才
    // 能渲染。主轴先出内容，补充随后补进来。
    final primary =
        _api.currentSource ?? (enabled.isNotEmpty ? enabled.first : null);

    // 首屏缓存命中：同步渲染旧数据（秒开），网络请求照常发起做后台刷新。
    // 未命中才走转圈 —— 这是「点 Tab 很慢」的核心优化：切回已看过的 Tab 不再等全量。
    final cacheKey = refresh
        ? _categoryFirstPageCacheKey(
            category,
            enabled,
            primary: primary,
            subClassId: subClassId,
            subClassAll: subClassAll,
          )
        : null;
    final cached = cacheKey == null ? null : _categoryFirstPageCache[cacheKey];
    if (refresh && cached != null) {
      // 注意：_categoryPage 保持 1 —— 后台刷新仍拉第 1 页，成功后照常
      // 置 2；这里若提前置 2，刷新会去拉第 2 页、把首屏内容换掉。
      _categoryMovies = List<Movie>.from(cached.movies);
      _hasMoreCategory = cached.hasMore;
      _categoryUnsupported = cached.unsupported;
      _isLoading = false;
      _errorMessage = '';
      _applyCategoryFilter();
      notifyListeners();
    } else if (refresh) {
      _isLoading = true;
      _isCategoryFirstPageLoading = true;
      notifyListeners();
    } else {
      _isLoadingMore = true;
      notifyListeners();
    }

    if (primary == null) {
      _categoryUnsupported = true;
      _categoryMovies = [];
      _categoryVisibleMovies = [];
      _hasMoreCategory = false;
      _isLoading = false;
      _isCategoryFirstPageLoading = false;
      _isLoadingMore = false;
      notifyListeners();
      return;
    }

    try {
      // 续页命中预取槽：直接用，不再打网络（首屏完成后已后台预拉下一页）。
      CmsListPage page;
      if (!refresh &&
          _categoryPrefetched != null &&
          _categoryPrefetched!.pageNo == _categoryPage &&
          _categoryPrefetched!.generation == generation) {
        page = _categoryPrefetched!.page;
        _categoryPrefetched = null;
      } else {
        page = await _api.fetchCategoryPageForSource(
          primary,
          category,
          region: region,
          year: year,
          genre: genre,
          page: _categoryPage,
          subClassId: _selectedSubClassId,
          allSubClasses: _subClassAll,
        );
      }
      _categoryPage = refresh ? 2 : _categoryPage + 1;

      // 代次守卫：期间用户又切了 Tab / 滚了续页，本次结果整体丢弃，
      // 不用旧首屏覆盖新状态（列表瞬间倒退）。
      if (generation != _categoryLoadGeneration) return;

      if (page.unsupported) {
        // 站点没有该分类：明确告知，而不是塞一批无关影片进来。
        _categoryUnsupported = true;
        _categoryMovies = [];
        _categoryVisibleMovies = [];
        _hasMoreCategory = false;
      } else {
        _categoryMovies = refresh
            ? page.movies
            : _appendCategoryDedup(_categoryMovies, page.movies);
        _hasMoreCategory = page.hasMore;
        if (refresh && cacheKey != null) {
          _writeCategoryFirstPageCache(cacheKey, page);
        }
      }

      // 首屏内容已就位：后台补补充源 + 预取下一页，都不阻塞首屏渲染。
      if (refresh && !page.unsupported) {
        unawaited(
          _supplementCategoryFromOtherSources(
            category: category,
            enabled: enabled,
            primary: primary,
            generation: generation,
            region: region,
            year: year,
            genre: genre,
            cacheKey: cacheKey,
            subClassId: _selectedSubClassId,
            subClassAll: _subClassAll,
          ),
        );
        unawaited(
          _prefetchNextCategoryPage(
            category: category,
            primary: primary,
            generation: generation,
            region: region,
            year: year,
            genre: genre,
            subClassId: _selectedSubClassId,
            subClassAll: _subClassAll,
          ),
        );
      }
      _errorMessage = '';
    } catch (e) {
      if (generation != _categoryLoadGeneration) return;
      _errorMessage = '加载分类影片失败: $e';
    } finally {
      // 过期代次不碰任何共享状态（新 Tab 的转圈/列表属于新一代次）。
      // 用 if 包裹而非 return —— finally 里的 return 会吞掉异常。
      if (generation == _categoryLoadGeneration) {
        if (refresh) {
          _isLoading = false;
          _isCategoryFirstPageLoading = false;
        } else {
          _isLoadingMore = false;
        }
        // 动态词表此时才确定：已选词若不在可用词表内，先回退再过滤，
        // 避免出现「筛选按一个词在跑、UI 却显示另一个词」的错位。
        final normalized = normalizeSelectedFilters(
          genre: _categoryGenreFilter,
          region: _categoryRegionFilter,
        );
        _categoryGenreFilter = normalized.genre;
        _categoryRegionFilter = normalized.region;
        _applyCategoryFilter();
        notifyListeners();
      }
    }
  }

  /// 详情页「换源」：按片名在其他启用源各搜第 1 页，挑出最像同一部片的候选。
  ///
  /// ⚠️ 各 CMS 的 `vod_id` 仅在本站唯一，**换源不能复用同一个 id**，必须重新
  /// 搜索匹配。每源只搜第 1 页（换源要的是「有没有」而不是翻页），源再多也
  /// 只打出与源数相当的请求；单个源失败只丢该候选，不影响其他源。
  ///
  /// 🔴 **不能等所有源都回来才出结果**（2026-10-23 用户实测「点击换源半天出不来」）：
  /// 搜索走的是 CMS 的 `ac=detail&wd=` 接口，单源响应可达数百 KB～1MB，
  /// 站点慢或超时时 `Future.wait` 会把所有源的最慢者当成整体耗时。
  /// 现在改成**增量投递**：任一源先回来就立刻回调 [onPartial]，
  /// UI 边收边显示；并给每个源单独设 [_sourceSwitchPerSourceTimeout] 兜底，
  /// 慢源被放弃而不是拖住整张表。
  ///
  /// [onPartial] 收到的是**截至此刻**的候选快照（按匹配分降序），
  /// 每次有源完成都会再调一次；调用方应据此刷新而不是等返回值。
  Future<List<DetailSourceCandidate>> searchMovieAcrossSources({
    required String keyword,
    required List<PlaySource> sources,
    String year = '',
    String? excludeSourceId,
    void Function(List<DetailSourceCandidate> snapshot)? onPartial,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const <DetailSourceCandidate>[];

    final targets = sources
        .where((s) => s.enabled && s.id != excludeSourceId)
        .toList(growable: false);
    if (targets.isEmpty) return const <DetailSourceCandidate>[];

    // 已确认的候选（按源去重，一个源只出一个最佳匹配）。
    final found = <DetailSourceCandidate>[];
    final foundSourceIds = <String>{};

    void publish() {
      if (onPartial == null) return;
      final snapshot = List<DetailSourceCandidate>.of(found)
        ..sort((a, b) => b.score.compareTo(a.score));
      onPartial(snapshot);
    }

    // 单源超时：慢源放弃，不拖累其它源（用户看到的是「已经找到几个」而不是干等）。
    Future<List<Movie>> searchOne(PlaySource s) async {
      try {
        return await _api
            .searchMovies(trimmed, maxPages: 1, source: s)
            .timeout(_sourceSwitchPerSourceTimeout);
      } catch (e) {
        debugPrint('换源搜索失败（源 ${s.name}）: $e');
        return const <Movie>[];
      }
    }

    // 分批并发（每批 [_sourceSwitchConcurrency] 个）：一次性打太多请求会被站点限流，
    // 反而更慢；分批既能并行，又不至于把对方站点打崩。
    for (var i = 0; i < targets.length; i += _sourceSwitchConcurrency) {
      final end = (i + _sourceSwitchConcurrency).clamp(0, targets.length);
      final batch = targets.sublist(i, end);
      final results = await Future.wait(batch.map(searchOne));
      for (var j = 0; j < batch.length; j++) {
        final source = batch[j];
        if (!foundSourceIds.add(source.id)) continue;
        final best = DetailSourceMatcher.pickBest(
          results[j],
          targetName: trimmed,
          targetYear: year,
        );
        if (best == null) continue;
        found.add(
          DetailSourceCandidate(
            source: source,
            movie: best,
            score: DetailSourceMatcher.score(
              candidateName: best.name,
              targetName: trimmed,
              candidateYear: best.year,
              targetYear: year,
            ),
          ),
        );
      }
      // 一批完成就投递一次：用户立刻看到已找到的候选。
      publish();
    }

    // 高分在前：最可能是同一部片的源排最上面。
    found.sort((a, b) => b.score.compareTo(a.score));
    return found;
  }

  /// 换源搜索：单个源的超时上限。
  ///
  /// 超时即放弃该源（它没匹配到就当没有），保证整体不会卡在某个慢站点上。
  static const Duration _sourceSwitchPerSourceTimeout = Duration(seconds: 8);

  /// 换源搜索：并发源数上限（分批打，避免被站点限流）。
  static const int _sourceSwitchConcurrency = 3;

  /// 首屏补充：其余启用源（限量 [categorySupplementMaxSources]）各拉第 1 页，
  /// 与已渲染数据去重后**追加**到末尾。
  ///
  /// 追加而非插队：不在用户眼前插条目导致列表跳动；主源内容始终在前面，
  /// 补充是「后面还有更多」。失败只记日志 —— 主源已可用，补充失败无感。
  Future<void> _supplementCategoryFromOtherSources({
    required String category,
    required List<PlaySource> enabled,
    required PlaySource primary,
    required int generation,
    required String region,
    required String year,
    required String genre,
    String? cacheKey,
    int? subClassId,
    bool subClassAll = false,
  }) async {
    final others = enabled
        .where((s) => s.id != primary.id)
        .take(categorySupplementMaxSources)
        .toList(growable: false);
    if (others.isEmpty) return;

    try {
      final pages = await Future.wait(
        others.map(
          (s) => _api.fetchCategoryPageForSource(
            s,
            category,
            region: region,
            year: year,
            genre: genre,
            page: 1,
            subClassId: subClassId,
            allSubClasses: subClassAll,
          ),
        ),
      );
      if (generation != _categoryLoadGeneration) return;

      final seen = <String>{
        for (final m in _categoryMovies) _movieDedupeKey(m),
      };
      final added = <Movie>[];
      for (final p in pages) {
        for (final m in p.movies) {
          if (seen.add(_movieDedupeKey(m))) added.add(m);
        }
      }
      if (added.isEmpty) return;

      _categoryMovies = <Movie>[..._categoryMovies, ...added];
      // 缓存回写完整首屏（主源 + 补充）：切回该类目时内容一致，
      // 不会出现「第一次 9 条、切回只剩主源 3 条」。
      if (cacheKey != null) {
        _writeCategoryFirstPageCache(
          cacheKey,
          CmsListPage(movies: _categoryMovies, hasMore: _hasMoreCategory),
        );
      }
      _applyCategoryFilter();
      notifyListeners();
    } catch (e) {
      debugPrint('类目补充源拉取失败（不影响主源）: $e');
    }
  }

  /// 后台预取主源下一页：首屏出内容后立刻拉，滚动续页时直接消费、不打网络。
  Future<void> _prefetchNextCategoryPage({
    required String category,
    required PlaySource primary,
    required int generation,
    required String region,
    required String year,
    required String genre,
    int? subClassId,
    bool subClassAll = false,
  }) async {
    if (!_hasMoreCategory) return;
    final next = _categoryPage; // 首屏成功后已是 2
    try {
      final page = await _api.fetchCategoryPageForSource(
        primary,
        category,
        region: region,
        year: year,
        genre: genre,
        page: next,
        subClassId: subClassId,
        allSubClasses: subClassAll,
      );
      if (generation != _categoryLoadGeneration) return;
      if (page.unsupported || page.movies.isEmpty) return;
      _categoryPrefetched = _CategoryPrefetchedPage(
          pageNo: next, page: page, generation: generation);
    } catch (e) {
      debugPrint('类目下一页预取失败（滚动时现拉）: $e');
    }
  }

  /// 写类目首屏缓存；超 [_categoryFirstPageCacheLimit] 淘汰最旧一条。
  void _writeCategoryFirstPageCache(String key, CmsListPage page) {
    if (_categoryFirstPageCache.length >= _categoryFirstPageCacheLimit &&
        !_categoryFirstPageCache.containsKey(key)) {
      final oldest = _categoryFirstPageCache.keys.first;
      _categoryFirstPageCache.remove(oldest);
    }
    _categoryFirstPageCache[key] = page;
  }

  /// 当前分类下的子类节点（首页「小分类」chip 的数据源）。
  ///
  /// 树未缓存（冷启动首次进 Tab）时返回空列表，UI 应隐藏该行而不是展示占位。
  List<CmsCategoryNode> get categorySubClasses =>
      _api.subClassesFor(_currentCategory);

  /// 当前选中的子类 type_id；null = 精选模式（首屏前 N 个子类）。
  int? get selectedSubClassId => _selectedSubClassId;

  /// 是否显式展开「全部」子类。
  bool get subClassAll => _subClassAll;

  /// 获取影片推荐
  Future<List<Movie>> getRecommendations(String movieId) async {
    try {
      return await _api.getRecommendations(movieId);
    } catch (e) {
      return [];
    }
  }

  /// 清除错误信息
  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }

  /// 直接设置当前影片（用于从列表页跳转时避免重复请求API）
  void setCurrentMovie(Movie movie) {
    _currentMovie = movie;
    notifyListeners();
  }

  /// 磁力详情等本地占位影片：不走 CMS，直接完成详情加载态。
  void completeDetailWithMovie(Movie movie) {
    _currentMovie = movie;
    _isLoadingDetail = false;
    _errorMessage = '';
    notifyListeners();
  }

  /// 打开叠层详情（如磁力详情）前保存当前详情状态。
  void pushDetailSnapshot() {
    _detailReturnSnapshot = _DetailReturnSnapshot(
      movie: _currentMovie,
      isLoadingDetail: _isLoadingDetail,
      errorMessage: _errorMessage,
    );
  }

  /// 离开叠层详情后恢复进入前的 CMS 详情状态。
  void popDetailSnapshot() {
    final snap = _detailReturnSnapshot;
    if (snap == null) return;
    _currentMovie = snap.movie;
    _isLoadingDetail = snap.isLoadingDetail;
    _errorMessage = snap.errorMessage;
    _detailReturnSnapshot = null;
    notifyListeners();
  }

  /// 设置当前源
  void setCurrentSource(PlaySource source) {
    _api.setCurrentSource(source);
  }

  /// 多源并发搜索
  ///
  /// 并发请求所有已启用的源，通过 Stream 流式返回结果。
  /// 每个源返回结果后立即更新 UI，实现流式追加展示效果。
  /// [sources] 为要搜索的源列表，由调用方从 SourceProvider 获取后传入。
  /// [relevance] 相关度模式：片名搜索用 strict（严格 + 空则放宽），
  /// 人名 / 类型搜索用 off（关键词不是片名，过滤只会把结果全杀掉）。
  Future<void> multiSourceSearch(
    String keyword, {
    required List<PlaySource> sources,
    SearchRelevance relevance = SearchRelevance.strict,
  }) async {
    // 取代次号：下面每一处写入前都比对，过期的一轮直接返回，
    // 不再覆盖新一轮的结果 / 提前关掉新一轮的 loading。
    final generation = ++_multiSearchGeneration;
    _isMultiSourceSearching = true;
    _multiSearchResults = [];
    _multiSearchKeyword = keyword;
    _searchStatusText = '正在搜索...';
    notifyListeners();

    try {
      final eventStream = _api.searchFromAllSources(
        keyword,
        sources: sources,
        relevance: relevance,
      );

      await for (final event in eventStream) {
        if (generation != _multiSearchGeneration) return;
        if (event is MultiSourceSearchProgress) {
          _multiSearchResults = event.results;
          _searchStatusText = event.statusText;
          notifyListeners();
        }
      }
    } catch (e) {
      if (generation != _multiSearchGeneration) return;
      debugPrint('多源搜索失败: $e');
      _searchStatusText = '搜索出错: $e';
      notifyListeners();
    }

    if (generation != _multiSearchGeneration) return;
    _isMultiSourceSearching = false;
    notifyListeners();
  }

  /// 获取个性化推荐
  ///
  /// 基于用户的观看历史和收藏，推荐相似类型的影片。
  /// 算法：
  /// 1. 从观看历史和收藏中提取用户偏好的类型（统计出现频率最高的3个类型）
  /// 2. 从所有影片中筛选这些类型的影片
  /// 3. 排除已观看和已收藏的
  /// 4. 按评分降序排列
  /// 5. 取前20条作为推荐
  ///
  /// [watchedMovieIds] 已观看的影片ID集合
  /// [favoriteMovieIds] 已收藏的影片ID集合
  /// [historyGenres] 观看历史中的影片类型列表
  /// [favoriteGenres] 收藏中的影片类型列表
  void getPersonalizedRecommendations({
    Set<String> watchedMovieIds = const {},
    Set<String> favoriteMovieIds = const {},
    List<String> historyGenres = const [],
    List<String> favoriteGenres = const [],
  }) {
    // 合并所有类型
    final allGenres = [...historyGenres, ...favoriteGenres];

    if (allGenres.isEmpty) {
      _personalizedRecommendations = [];
      notifyListeners();
      return;
    }

    // 统计类型出现频率
    final genreCount = <String, int>{};
    for (final genre in allGenres) {
      if (genre.isNotEmpty) {
        genreCount[genre] = (genreCount[genre] ?? 0) + 1;
      }
    }

    // 按频率排序，取前3个类型
    final topGenres = genreCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final preferredGenres = topGenres.take(3).map((e) => e.key).toSet();

    // 合并已观看和已收藏的ID集合
    final excludeIds = {...watchedMovieIds, ...favoriteMovieIds};

    // 从首页影片列表中筛选匹配类型的影片
    final allMovies = [
      ..._homeMovies,
      ..._hotMovies,
      ..._latestMovies,
      ..._topRatedMovies,
      ..._classicMovies,
    ];

    // 去重（按id）
    final seenIds = <String>{};
    final uniqueMovies = <Movie>[];
    for (final movie in allMovies) {
      if (!seenIds.contains(movie.id)) {
        seenIds.add(movie.id);
        uniqueMovies.add(movie);
      }
    }

    // 筛选匹配类型且不在排除列表中的影片
    final recommendations = uniqueMovies.where((movie) {
      // 排除已观看和已收藏的
      if (excludeIds.contains(movie.id)) return false;
      // 检查类型是否匹配
      return movie.genres.any((g) => preferredGenres.contains(g));
    }).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));

    _personalizedRecommendations = recommendations.take(20).toList();
    notifyListeners();
  }
}

class _DetailReturnSnapshot {
  const _DetailReturnSnapshot({
    required this.movie,
    required this.isLoadingDetail,
    required this.errorMessage,
  });

  final Movie? movie;
  final bool isLoadingDetail;
  final String errorMessage;
}

/// 类目后台预取的一页（主源续页用）。
///
/// [generation] 用于丢弃过期预取：切 Tab 前预取的页不能给新类目用。
class _CategoryPrefetchedPage {
  const _CategoryPrefetchedPage({
    required this.pageNo,
    required this.page,
    required this.generation,
  });

  final int pageNo;
  final CmsListPage page;
  final int generation;
}

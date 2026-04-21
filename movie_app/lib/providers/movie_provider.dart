import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/movie.dart';
import '../models/play_source.dart';
import '../services/api_service.dart';

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

  /// 分类影片列表
  List<Movie> _categoryMovies = [];

  /// 是否正在加载（首页等，勿与详情加载混用）
  bool _isLoading = false;

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 详情页专用，避免与 [loadHomeData] 共享 [_isLoading] 产生竞态（首页先结束会把详情误判为失败）
  bool _isLoadingDetail = false;

  /// 是否正在加载影片详情
  bool get isLoadingDetail => _isLoadingDetail;

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

  /// 分类列表是否已加载
  bool _categoriesLoaded = false;

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

  // Getter
  List<Movie> get bannerList => _bannerList;
  List<Movie> get homeMovies => _homeMovies;
  List<Movie> get hotMovies => _hotMovies;
  List<Movie> get latestMovies => _latestMovies;
  List<Movie> get topRatedMovies => _topRatedMovies;
  List<Movie> get classicMovies => _classicMovies;
  Movie? get currentMovie => _currentMovie;
  List<Movie> get categoryMovies => _categoryMovies;
  bool get hasMoreCategory => _hasMoreCategory;
  String get currentCategory => _currentCategory;

  /// 首页是否还有更多数据
  bool get hasMoreHome => _hasMoreHome;

  /// 首页是否正在加载更多
  bool get isLoadingMore => _isLoadingMore;

  /// 获取分类列表（从API缓存中获取）
  Map<int, String> get categories => _api.categoryMap;

  /// 分类列表是否已加载
  bool get categoriesLoaded => _categoriesLoaded;

  /// 初始化
  Future<void> init() async {
    await _api.init();
  }

  /// 加载首页数据（分区独立加载，互不影响）
  Future<void> loadHomeData() async {
    if (_isLoading) return;
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
      _isLoading = false;
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

  /// 加载更多首页数据（无限滚动）
  Future<void> loadMoreHome() async {
    if (_isLoadingMore || !_hasMoreHome) return;
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
  Future<void> loadMovieDetail(String movieId) async {
    primeDetailLoad(movieId);

    try {
      _currentMovie = await _api.getMovieDetail(movieId);
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
  Future<void> loadCategoryMovies({
    required String category,
    String region = '',
    String year = '',
    String sort = '',
    String genre = '',
    bool refresh = false,
    List<PlaySource>? mergeSources,
  }) async {
    if (refresh) {
      _categoryPage = 1;
      _categoryMovies = [];
      _hasMoreCategory = true;
    }

    if (!_hasMoreCategory) return;

    _currentCategory = category;
    if (refresh) {
      _isLoading = true;
    } else {
      _isLoadingMore = true;
    }
    notifyListeners();

    try {
      if (refresh &&
          mergeSources != null &&
          mergeSources.where((s) => s.enabled).length > 1) {
        final enabled = mergeSources.where((s) => s.enabled).toList();
        final agg = await _api.aggregateCategoryFirstPage(
          sources: enabled,
          category: category,
          region: region,
          genre: genre,
        );
        _categoryMovies = agg.movies;
        _hasMoreCategory = agg.hasMore;
        _categoryPage = 2;
        _errorMessage = '';
      } else {
        final page = await _api.getMoviesByCategory(
          category: category,
          region: region,
          year: year,
          sort: sort,
          genre: genre,
          page: _categoryPage,
        );

        if (refresh) {
          _categoryMovies = page.movies;
        } else {
          _categoryMovies = [..._categoryMovies, ...page.movies];
        }

        _hasMoreCategory = page.hasMore;
        _categoryPage++;
        _errorMessage = '';
      }
    } catch (e) {
      _errorMessage = '加载分类影片失败: $e';
    } finally {
      if (refresh) {
        _isLoading = false;
      } else {
        _isLoadingMore = false;
      }
      notifyListeners();
    }
  }

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

  /// 设置当前源
  void setCurrentSource(PlaySource source) {
    _api.setCurrentSource(source);
    // 切换源时重置分类加载状态
    _categoriesLoaded = false;
  }

  /// 加载分类列表（懒加载，首次调用时请求API）
  Future<void> loadCategories() async {
    if (_categoriesLoaded) return;
    await _api.loadCategories();
    _categoriesLoaded = true;
    notifyListeners();
  }

  /// 多源并发搜索
  ///
  /// 并发请求所有已启用的源，通过 Stream 流式返回结果。
  /// 每个源返回结果后立即更新 UI，实现流式追加展示效果。
  /// [sources] 为要搜索的源列表，由调用方从 SourceProvider 获取后传入。
  Future<void> multiSourceSearch(
    String keyword, {
    required List<PlaySource> sources,
  }) async {
    _isMultiSourceSearching = true;
    _multiSearchResults = [];
    _searchStatusText = '正在搜索...';
    notifyListeners();

    try {
      final eventStream = _api.searchFromAllSources(
        keyword,
        sources: sources,
      );

      await for (final event in eventStream) {
        if (event is MultiSourceSearchProgress) {
          _multiSearchResults = event.results;
          _searchStatusText = event.statusText;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('多源搜索失败: $e');
      _searchStatusText = '搜索出错: $e';
      notifyListeners();
    }

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

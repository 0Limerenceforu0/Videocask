import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../config/app_env.dart';
import '../config/constants.dart';
import '../models/movie.dart';
import '../models/play_source.dart';
import 'network/dio_factory.dart';
import '../utils/commentary_content_filter.dart';
import 'error_handler.dart';

// 条件导入：Web端使用 dart:html 的 HttpRequest，非Web端使用 stub
import '../utils/web_http_stub.dart'
    if (dart.library.html) '../utils/web_http.dart' as web_http;

/// CMS 列表单页结果（含是否还有下一页，避免条数 <20 时误停分页）
class CmsListPage {
  final List<Movie> movies;
  final bool hasMore;

  const CmsListPage({required this.movies, required this.hasMore});
}

/// API服务 - 兼容苹果CMS采集接口格式
///
/// 苹果CMS采集接口说明：
/// - 影片列表：GET {url}?ac=detail&t={分类ID}&pg={页码}
/// - 影片详情：GET {url}?ac=detail&ids={影片ID}
/// - 搜索影片：GET {url}?ac=detail&wd={关键词}&pg={页码}
/// - 分类列表：GET {url}?ac=list（返回中包含class字段）
///
/// Web端通过CORS代理转发请求，绕过浏览器跨域限制
class ApiService {
  ApiService._();
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;

  /// Dio实例（非Web端使用）
  Dio? _dio;

  /// 是否已初始化
  bool _initialized = false;

  /// 当前使用的源
  PlaySource? _currentSource;

  /// 当前源
  PlaySource? get currentSource => _currentSource;

  /// 分类列表缓存（type_id → type_name）
  Map<int, String> _categoryMap = {};

  /// 分类列表缓存
  Map<int, String> get categoryMap => _categoryMap;

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 自动化测试模式：避免创建真实 HttpClient / Dio，防止测试环境产生 400 噪声与不稳定因素。
    if (AppEnv.isTestMode) {
      debugPrint('测试模式：跳过 Dio 初始化');
      return;
    }

    // Web端不需要初始化 Dio（所有请求通过 dart:html HttpRequest 发送）
    if (kIsWeb) {
      debugPrint('Web 端跳过 Dio 初始化');
      return;
    }

    _dio = await DioFactory.plainText();

    // 添加拦截器
    _dio!.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint('API请求: ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          handler.next(response);
        },
        onError: (error, handler) {
          debugPrint('API错误: ${error.message}');
          handler.next(error);
        },
      ),
    );
  }

  /// 设置当前源
  void setCurrentSource(PlaySource source) {
    _currentSource = source;
    // 切换源时清空分类缓存
    _categoryMap = {};
  }

  /// 获取所有可用源列表（由 SourceProvider 设置）
  /// 用于当当前源请求失败时自动切换到其他源
  List<PlaySource> _availableSources = [];

  /// 设置可用源列表
  void setAvailableSources(List<PlaySource> sources) {
    _availableSources = sources;
  }

  /// 源切换回调（通知 SourceProvider 更新当前源）
  void Function(PlaySource source)? onSourceSwitched;

  /// 源切换提示信息（供 UI 层展示给用户）
  /// 格式：["源A无数据", "切换到源B", "源B成功"]
  List<String> sourceSwitchMessages = [];

  /// 用指定源尝试请求，失败自动切换到下一个可用源
  ///
  /// 会尝试所有启用的源，直到找到返回有效数据的源。
  /// 切换过程记录在 [sourceSwitchMessages] 中，供 UI 展示提示。
  ///
  /// [requestFn] 接收一个 PlaySource 参数，返回请求结果
  /// [isValidResult] 可选的验证函数，用于判断结果是否有效
  Future<T?> _requestWithFallback<T>(
    Future<T?> Function(PlaySource source) requestFn, {
    bool Function(T? result)? isValidResult,
  }) async {
    if (_currentSource == null) return null;

    sourceSwitchMessages.clear();

    // 收集所有启用的源：当前源优先，然后是其他源
    final enabledSources = _availableSources.where((s) => s.enabled).toList();
    final otherSources =
        enabledSources.where((s) => s.id != _currentSource!.id).toList();

    final sourcesToTry = <PlaySource>[
      if (_currentSource!.enabled) _currentSource!,
      ...otherSources,
    ];

    for (int i = 0; i < sourcesToTry.length; i++) {
      final source = sourcesToTry[i];

      // 如果不是当前源，切换并记录
      if (source.id != _currentSource?.id) {
        debugPrint('🔄 当前源 "${_currentSource?.name}" 无数据，切换到 "${source.name}"');
        sourceSwitchMessages
            .add('源 "${_currentSource?.name}" 无数据，切换到 "${source.name}"');
        _currentSource = source;
        _categoryMap = {};
        onSourceSwitched?.call(source);
      }

      try {
        final result = await requestFn(source);

        bool isValid = false;
        if (isValidResult != null) {
          isValid = isValidResult(result);
        } else if (result is List) {
          isValid = result.isNotEmpty;
        } else if (result is Map) {
          isValid = result.isNotEmpty;
        } else if (result != null) {
          isValid = true;
        }

        if (isValid) {
          if (i > 0) {
            // 不是第一个源就成功了，记录提示
            sourceSwitchMessages.add('已切换到 "${source.name}" 加载数据');
          }
          return result;
        }

        // 当前源返回无效数据
        if (i < sourcesToTry.length - 1) {
          debugPrint('⚠️ 源 "${source.name}" 返回无效数据，尝试下一个源...');
          sourceSwitchMessages.add('源 "${source.name}" 无数据');
        }
      } catch (e) {
        debugPrint('⚠️ 源 "${source.name}" 请求异常: $e');
        sourceSwitchMessages.add('源 "${source.name}" 请求失败');
        if (i < sourcesToTry.length - 1) {
          debugPrint('尝试下一个源...');
        }
      }
    }

    // 所有源都失败
    sourceSwitchMessages.add('所有源均无法加载数据');
    return null;
  }

  /// 发起HTTP GET请求
  ///
  /// Web端通过CORS代理转发，非Web端直接使用Dio
  Future<String?> _httpGet(String url) async {
    if (AppEnv.isTestMode) return null;
    if (kIsWeb) {
      try {
        return web_http.webRequestForApi(url);
      } catch (e) {
        debugPrint('Web HTTP请求失败: ${ErrorHandler().handleNetworkError(e)}');
        return null;
      }
    } else {
      try {
        if (_dio == null) {
          await init();
        }
        final response = await _dio!.get(url);
        if (response.data is String) {
          return response.data as String;
        }
        debugPrint('Dio响应数据异常: ${response.data}');
        return null;
      } catch (e) {
        debugPrint('HTTP请求失败: ${ErrorHandler().handleNetworkError(e)}');
        return null;
      }
    }
  }

  /// 获取首页数据
  ///
  /// 分别请求不同分类的数据填充各区域，避免所有区域数据重复。
  /// 当当前源无数据时，自动切换到其他可用源。
  Future<HomeData> getHomeData() async {
    // 自动化测试模式：不依赖外部接口，直接返回模拟数据，保证 UI 与流程可跑通。
    if (AppEnv.isTestMode) {
      return HomeData.empty();
    }
    if (_currentSource == null) {
      return HomeData.empty();
    }

    try {
      HomeData? result;

      await _requestWithFallback<HomeData>(
        (source) async {
          // 并发请求多个分类的数据（首次加载5页，确保用户滚动时有充足数据）
          final futures = <Future<List<Movie>>>[
            // 最近更新：请求第1页，取全部
            _fetchCmsListForSource(source, page: 1),
            // 热门影视：请求第2页，获取不同的数据
            _fetchCmsListForSource(source, page: 2),
            // 高分推荐：请求第3页
            _fetchCmsListForSource(source, page: 3),
            // 预加载第4页（提前准备，滚动无感）
            _fetchCmsListForSource(source, page: 4),
            // 预加载第5页
            _fetchCmsListForSource(source, page: 5),
          ];

          final results = await Future.wait(futures);

          final page1Movies = results[0]; // 最近更新
          final page2Movies = results[1]; // 热门影视
          final page3Movies = results[2]; // 高分推荐
          final page4Movies = results[3]; // 预加载
          final page5Movies = results[4]; // 预加载

          if (page1Movies.isEmpty &&
              page2Movies.isEmpty &&
              page3Movies.isEmpty) {
            return null; // 触发 fallback
          }

          debugPrint('📊 首页数据加载完成 (${source.name}): '
              '最近${page1Movies.length}条, 热门${page2Movies.length}条, 高分${page3Movies.length}条, '
              '预加载${page4Movies.length + page5Movies.length}条');

          // Banner：从第1页取前5个
          final bannerList = page1Movies.length > 5
              ? page1Movies.sublist(0, 5)
              : List<Movie>.from(page1Movies);

          // 高分推荐：合并所有数据，按评分排序取前30
          final allMovies = [
            ...page1Movies,
            ...page2Movies,
            ...page3Movies,
            ...page4Movies,
            ...page5Movies,
          ];
          final sortedByRating = List<Movie>.from(allMovies)
            ..sort((a, b) {
              final c = b.rating.compareTo(a.rating);
              if (c != 0) return c;
              return a.id.compareTo(b.id);
            });
          final topRatedMovies = sortedByRating.length > 30
              ? sortedByRating.sublist(0, 30)
              : sortedByRating;

          result = HomeData(
            bannerList: bannerList,
            hotMovies: page2Movies.isNotEmpty ? page2Movies : page1Movies,
            latestMovies: page1Movies,
            topRatedMovies: topRatedMovies,
            classicMovies: page3Movies.isNotEmpty ? page3Movies : page1Movies,
          );
          return result!;
        },
      );

      if (result == null) {
        debugPrint('API未返回数据，使用模拟数据展示');
        return HomeData.empty();
      }

      return result!;
    } catch (e) {
      debugPrint('获取首页数据失败: $e');
      return HomeData.empty();
    }
  }

  /// 获取影片详情
  ///
  /// 苹果CMS详情接口：GET {url}?ac=detail&ids={影片ID}
  Future<Movie?> getMovieDetail(
    String movieId, {
    bool allowFallback = true,
  }) async {
    // 自动化测试模式：返回一个可渲染的详情对象，避免依赖外部接口。
    if (AppEnv.isTestMode) {
      return Movie(
        id: movieId.isEmpty ? 'mock_detail_1' : movieId,
        name: '示例影片（详情）',
        rating: 8.5,
        genres: const ['动作', '科幻'],
        year: '2024',
        updateStatus: '更新至第1集',
      );
    }
    if (_currentSource == null) return null;

    try {
      Movie? result;
      Future<Movie?> fetchFromSource(PlaySource source) async {
        final url = '${source.url}?ac=detail&ids=$movieId';
        final rawData = await _httpGet(url);
        if (rawData == null) {
          return null;
        }

        final data = _parseResponseData(rawData);
        if (data == null) {
          return null;
        }

        final listRaw = data['list'];
        if (listRaw is! List || listRaw.isEmpty) {
          return null;
        }

        return Movie.fromCmsJson(listRaw[0] as Map<String, dynamic>);
      }

      if (allowFallback) {
        result = await _requestWithFallback<Movie>(
          (source) async {
            return await fetchFromSource(source);
          },
          isValidResult: (movie) => _hasPlayableEpisode(movie),
        );
        // 接口能返回影片元数据但暂无可解析播放地址时，仍展示详情页（避免整页错误）
        if (result == null) {
          debugPrint('📊 影片详情: id=$movieId, 无可用播放线路，回退为仅元数据');
          result = await _requestWithFallback<Movie>(
            (source) async {
              return await fetchFromSource(source);
            },
            isValidResult: (movie) => movie != null,
          );
        }
      } else {
        result = await fetchFromSource(_currentSource!);
      }

      if (result != null) {
        debugPrint('📊 影片详情: id=$movieId, 成功');
      } else {
        debugPrint('📊 影片详情: id=$movieId, 失败');
      }
      return result;
    } catch (e) {
      debugPrint('获取影片详情失败: $e');
      debugPrint('📊 影片详情: id=$movieId, 失败');
      return null;
    }
  }

  /// 判断详情是否含有至少一个可用播放地址
  bool _hasPlayableEpisode(Movie? movie) {
    if (movie == null) return false;
    for (final route in movie.playRoutes) {
      for (final ep in route.episodes) {
        if (ep.url.trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  /// 搜索影片
  ///
  /// 苹果CMS搜索接口：GET {url}?ac=detail&wd={关键词}&pg={页码}
  Future<List<Movie>> searchMovies(String keyword, {int page = 1}) async {
    // 自动化测试模式：返回稳定的模拟搜索结果，便于验证搜索页面交互与列表渲染。
    if (AppEnv.isTestMode) {
      if (keyword.trim().isEmpty) return [];
      return List<Movie>.generate(
        10,
        (i) => Movie(
          id: 'mock_search_${page}_$i',
          name: '搜索结果 ${i + 1}：$keyword',
          rating: 7.5,
          genres: const ['剧情'],
          year: '2024',
          updateStatus: i.isEven ? '已完结' : '更新中',
        ),
      );
    }
    if (_currentSource == null) return [];
    if (keyword.trim().isEmpty) return [];

    try {
      final url =
          '${_currentSource!.url}?ac=detail&wd=${Uri.encodeQueryComponent(keyword)}&pg=$page';
      final rawData = await _httpGet(url);
      if (rawData == null) return [];

      final movies = _parseMovieListFromResponse(rawData);
      debugPrint('📊 搜索结果: keyword=$keyword, 获取到 ${movies.length} 条');
      return movies;
    } catch (e) {
      debugPrint('搜索影片失败: $e');
      return [];
    }
  }

  /// 将 Tab 上的分类名映射为采集站里的 type_name（模糊匹配）
  int? _resolveCategoryTypeId(String category) {
    return _resolveCategoryTypeIdForMap(_categoryMap, category);
  }

  int? _resolveCategoryTypeIdForMap(Map<int, String> map, String category) {
    if (map.isEmpty) return null;
    for (final entry in map.entries) {
      if (entry.value == category) return entry.key;
    }
    final aliases = <String, List<String>>{
      '剧集': ['电视剧', '剧集', '连续剧', '国产剧', '韩剧'],
      '电影': ['电影', '影片'],
      '动漫': ['动漫', '动画'],
      '综艺': ['综艺'],
      '纪录片': ['纪录片', '纪录'],
    };
    final tryNames = aliases[category] ?? [category];
    for (final name in tryNames) {
      for (final entry in map.entries) {
        if (entry.value == name ||
            entry.value.contains(name) ||
            name.contains(entry.value)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  static String _dedupeKeyForMovie(Movie m) {
    final y = (m.year.isEmpty || m.year == '0') ? '' : m.year;
    final n = m.name.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return '$n|$y';
  }

  /// 任意源的分类列表（不修改当前源缓存，用于多源聚合）
  Future<Map<int, String>> _fetchCategoryListForSourceUrl(
    String sourceUrl,
  ) async {
    try {
      final url =
          sourceUrl.contains('?') ? '$sourceUrl&ac=list' : '$sourceUrl?ac=list';
      final rawData = await _httpGet(url);
      if (rawData == null) return {};

      final data = _parseResponseData(rawData);
      if (data == null) return {};

      final classRaw = data['class'];
      if (classRaw is! List) return {};

      final out = <int, String>{};
      for (final item in classRaw) {
        if (item is! Map<String, dynamic>) continue;
        final typeId = int.tryParse(item['type_id'].toString()) ?? 0;
        final typeName = item['type_name']?.toString() ?? '';
        if (typeId > 0 && typeName.isNotEmpty) {
          out[typeId] = typeName;
        }
      }
      return out;
    } catch (e) {
      debugPrint('获取外部分类列表失败: $e');
      return {};
    }
  }

  /// 从指定播放源拉取分类列表的一页（多源首页用）
  Future<CmsListPage> fetchCategoryPageForSource(
    PlaySource source,
    String category, {
    String region = '',
    String genre = '',
    int page = 1,
  }) async {
    final map = await _fetchCategoryListForSourceUrl(source.url);
    final typeId = _resolveCategoryTypeIdForMap(map, category);
    if (typeId == null) {
      debugPrint('⚠️ 源 ${source.name} 未匹配到分类「$category」');
    }
    return _fetchCmsListPageForSource(
      source,
      page: page,
      typeId: typeId,
      area: region,
      clazz: genre,
    );
  }

  /// 分类首屏：并发拉取各已启用源的第 1 页并去重合并；[hasMore] 取当前主源对应条目的翻页标志
  Future<CmsListPage> aggregateCategoryFirstPage({
    required List<PlaySource> sources,
    required String category,
    String region = '',
    String genre = '',
  }) async {
    if (sources.isEmpty) {
      return const CmsListPage(movies: [], hasMore: false);
    }
    final results = await Future.wait(
      sources.map(
        (s) => fetchCategoryPageForSource(
          s,
          category,
          region: region,
          genre: genre,
          page: 1,
        ),
      ),
    );

    final seen = <String>{};
    final merged = <Movie>[];
    for (final r in results) {
      for (final m in r.movies) {
        final k = _dedupeKeyForMovie(m);
        if (seen.contains(k)) continue;
        seen.add(k);
        merged.add(m);
      }
    }
    merged.sort((a, b) {
      final c = b.rating.compareTo(a.rating);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });

    var primaryHasMore = results.first.hasMore;
    final curId = _currentSource?.id;
    if (curId != null && curId.isNotEmpty) {
      for (var i = 0; i < sources.length; i++) {
        if (sources[i].id == curId) {
          primaryHasMore = results[i].hasMore;
          break;
        }
      }
    }

    return CmsListPage(movies: merged, hasMore: primaryHasMore);
  }

  /// 获取分类影片
  ///
  /// 苹果CMS分类接口：GET {url}?ac=detail&t={分类ID}&pg={页码}
  /// 可选：area、class（类型）、year（部分站点支持）
  /// [category] 为分类名称（如"电影"、"电视剧"），需要映射为分类ID
  Future<CmsListPage> getMoviesByCategory({
    required String category,
    String region = '',
    String year = '',
    String sort = '',
    String genre = '',
    int page = 1,
  }) async {
    if (_currentSource == null) {
      return const CmsListPage(movies: [], hasMore: false);
    }

    try {
      if (_categoryMap.isEmpty) {
        await _fetchCategoryList();
      }

      final typeId = _resolveCategoryTypeId(category);
      if (typeId == null) {
        debugPrint('⚠️ 未匹配到分类「$category」，当前站点类型: $_categoryMap');
      }

      return _fetchCmsListPageForSource(
        _currentSource,
        page: page,
        typeId: typeId,
        area: region,
        clazz: genre,
        year: year,
      );
    } catch (e) {
      debugPrint('获取分类影片失败: $e');
      return const CmsListPage(movies: [], hasMore: false);
    }
  }

  /// 获取分类列表（公开方法，支持懒加载）
  ///
  /// 苹果CMS分类接口：GET {url}?ac=list
  /// 返回中包含class字段
  /// 首次调用时请求API，后续直接返回缓存
  Future<Map<int, String>> loadCategories() async {
    // 如果已有缓存，直接返回
    if (_categoryMap.isNotEmpty) return _categoryMap;
    return _fetchCategoryList();
  }

  /// 获取分类列表（内部方法）
  ///
  /// 苹果CMS分类接口：GET {url}?ac=list
  /// 返回中包含class字段
  Future<Map<int, String>> _fetchCategoryList() async {
    if (_currentSource == null) return {};

    try {
      final url = '${_currentSource!.url}?ac=list';
      final rawData = await _httpGet(url);
      if (rawData == null) return {};

      final data = _parseResponseData(rawData);
      if (data == null) return {};

      // 安全检查 class 字段类型
      final classRaw = data['class'];
      if (classRaw is! List) return {};

      _categoryMap = {};
      for (final item in classRaw) {
        if (item is! Map<String, dynamic>) continue;
        // type_id 可能是 String 类型，需要安全转换
        final typeId = int.tryParse(item['type_id'].toString()) ?? 0;
        final typeName = item['type_name']?.toString() ?? '';
        if (typeId > 0 && typeName.isNotEmpty) {
          _categoryMap[typeId] = typeName;
        }
      }

      debugPrint('📊 获取分类列表: ${_categoryMap.length} 个分类');
      return _categoryMap;
    } catch (e) {
      debugPrint('获取分类列表失败: $e');
      return {};
    }
  }

  /// 获取指定页的影片列表（公开方法，供 Provider 调用）
  ///
  /// 苹果CMS接口：GET {url}?ac=detail&pg={页码}
  /// 用于首页无限滚动加载更多数据
  Future<CmsListPage> fetchMoviesByPage(int page) async {
    return _fetchCmsListPageForSource(_currentSource, page: page);
  }

  /// 获取CMS列表单页（指定源）及是否还有下一页
  Future<CmsListPage> _fetchCmsListPageForSource(
    PlaySource? source, {
    int page = 1,
    int? typeId,
    String area = '',
    String clazz = '',
    String year = '',
  }) async {
    if (source == null) {
      return const CmsListPage(movies: [], hasMore: false);
    }

    try {
      final queryParameters = <String, String>{
        'ac': 'detail',
        'pg': page.toString(),
      };

      if (typeId != null) {
        queryParameters['t'] = typeId.toString();
      }

      if (area.isNotEmpty && area != '全部') {
        queryParameters['area'] = area;
      }
      if (clazz.isNotEmpty && clazz != '全部') {
        queryParameters['class'] = clazz;
      }
      if (year.isNotEmpty && year != '全部' && year != '更早') {
        queryParameters['year'] = year;
      }

      final uri =
          Uri.parse(source.url).replace(queryParameters: queryParameters);
      final rawData = await _httpGet(uri.toString());
      if (rawData == null) {
        return const CmsListPage(movies: [], hasMore: false);
      }

      final json = _parseResponseData(rawData);
      if (json == null) {
        return const CmsListPage(movies: [], hasMore: false);
      }

      final listRaw = json['list'];
      if (listRaw is! List || listRaw.isEmpty) {
        return const CmsListPage(movies: [], hasMore: false);
      }

      final movies = listRaw
          .whereType<Map<String, dynamic>>()
          .map((e) => Movie.fromCmsJson(e).copyWith(sourceId: source.id))
          .toList();

      final pg = int.tryParse(json['page']?.toString() ?? '1') ?? 1;
      final pagecount = int.tryParse(json['pagecount']?.toString() ?? '0') ?? 0;
      final limit = int.tryParse(
            json['limit']?.toString() ?? '${AppConstants.pageSize}',
          ) ??
          AppConstants.pageSize;

      final bool hasMore;
      if (pagecount > 0) {
        hasMore = pg < pagecount;
      } else {
        hasMore = movies.length >= limit;
      }

      debugPrint('📊 获取列表数据: page=$page, ${movies.length} 条, hasMore=$hasMore');
      return CmsListPage(movies: movies, hasMore: hasMore);
    } catch (e, stackTrace) {
      debugPrint('获取列表数据失败: $e');
      debugPrint('堆栈: $stackTrace');
      return const CmsListPage(movies: [], hasMore: false);
    }
  }

  /// 获取CMS列表数据（指定源，仅影片列表）
  Future<List<Movie>> _fetchCmsListForSource(
    PlaySource? source, {
    int page = 1,
    int? typeId,
    String area = '',
    String clazz = '',
    String year = '',
  }) async {
    final p = await _fetchCmsListPageForSource(
      source,
      page: page,
      typeId: typeId,
      area: area,
      clazz: clazz,
      year: year,
    );
    return p.movies;
  }

  /// 解析API响应中的影片列表
  List<Movie> _parseMovieListFromResponse(dynamic data) {
    try {
      final json = _parseResponseData(data);
      if (json == null) return [];

      // 安全检查 list 字段类型
      final listRaw = json['list'];
      if (listRaw is! List || listRaw.isEmpty) return [];

      return listRaw
          .whereType<Map<String, dynamic>>()
          .map((e) => Movie.fromCmsJson(e))
          .where((m) => !CommentaryContentFilter.isMovie(m))
          .toList();
    } catch (e) {
      debugPrint('解析影片列表失败: $e');
      return [];
    }
  }

  /// 解析响应数据
  ///
  /// 苹果CMS返回格式：
  /// {
  ///   "code": 200,
  ///   "msg": "ok",
  ///   "page": 1,
  ///   "pagecount": 100,
  ///   "limit": "20",
  ///   "total": 2000,
  ///   "list": [...],
  ///   "class": [...]
  /// }
  Map<String, dynamic>? _parseResponseData(dynamic data) {
    try {
      Map<String, dynamic> json;
      if (data is String) {
        // 清理字符串：去除 BOM、尾部空白、控制字符
        String cleaned = data.trim();
        cleaned =
            cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
        json = jsonDecode(cleaned) as Map<String, dynamic>;
      } else if (data is Map<String, dynamic>) {
        json = data;
      } else {
        return null;
      }

      // 检查返回码（苹果CMS通常返回1或200表示成功）
      final code = json['code'];
      if (code != null &&
          code != 200 &&
          code != '200' &&
          code != 1 &&
          code != '1') {
        debugPrint('API返回错误码: $code, 消息: ${json['msg']}');
        return null;
      }

      return json;
    } catch (e) {
      debugPrint('解析响应数据失败: $e');
      return null;
    }
  }

  /// 解析播放地址
  Future<String?> parsePlayUrl(String rawUrl) async {
    if (rawUrl.isEmpty) return null;

    // 如果已经是直接的播放地址
    if (rawUrl.startsWith('http') &&
        (rawUrl.contains('.mp4') ||
            rawUrl.contains('.m3u8') ||
            rawUrl.contains('.mkv'))) {
      return rawUrl;
    }

    // 如果是相对路径，拼接源地址
    if (rawUrl.startsWith('/')) {
      return '${_currentSource?.url ?? ''}$rawUrl';
    }

    // 苹果CMS的播放地址通常已经是完整的URL，直接返回
    if (rawUrl.startsWith('http')) {
      return rawUrl;
    }

    // 其他情况尝试直接返回
    return rawUrl;
  }

  /// 检测源是否有效
  ///
  /// 苹果CMS检测方式：GET {url}?ac=list
  /// 检查是否返回200状态码和正确的JSON格式
  Future<bool> checkSource(PlaySource source) async {
    try {
      final url = '${source.url}?ac=list';
      final rawData = await _httpGet(url);
      if (rawData == null) return false;

      final json = jsonDecode(rawData) as Map<String, dynamic>;
      final code = json['code'];
      return code == 200 || code == '200' || code == 1 || code == '1';
    } catch (e) {
      debugPrint('检测源失败: ${source.url}, 错误: $e');
      return false;
    }
  }

  /// 去掉片名末尾季数，便于搜到同系列其它季（如「…第四季」→「…这档事」前的基名）。
  static String stripSeasonFromTitleForRecommend(String name) {
    var t = name.trim();
    final m1 = RegExp(r'第[一二三四五六七八九十百千万零两〇0-9]+季').firstMatch(t);
    if (m1 != null && m1.start > 0) {
      return t.substring(0, m1.start).trim();
    }
    final m2 = RegExp(r'(?:第)?[一二三四五六七八九十0-9]+季\s*$').firstMatch(t);
    if (m2 != null && m2.start >= 2) {
      return t.substring(0, m2.start).trim();
    }
    t = t.replaceAll(RegExp(r'\s*[Ss]\d{1,2}\s*$'), '').trim();
    return t;
  }

  /// 详情页侧栏「相关推荐」：用**类型、去季片名、全名**等对当前源做 `wd` 搜索并去重合并。
  ///
  /// 苹果 CMS 无独立推荐接口；旧逻辑仅用 [Movie.genres] 第一项且常与 [_loadData] 竞态，导致大量「暂无推荐」。
  Future<List<Movie>> getDetailSideRecommendations(Movie movie) async {
    if (_currentSource == null) return [];

    if (AppEnv.isTestMode) {
      return List<Movie>.generate(
        5,
        (i) => Movie(
          id: 'mock_rec_$i',
          name: '推荐 ${i + 1}（${movie.name}）',
          rating: 8.0,
          genres: movie.genres.isNotEmpty ? movie.genres : const ['剧情'],
          year: movie.year.isNotEmpty ? movie.year : '2024',
        ),
      );
    }

    final movieId = movie.id;
    final out = <Movie>[];
    final seen = <String>{};

    Future<void> tryKeyword(String raw) async {
      final kw = raw.trim();
      if (kw.length < 2) return;
      try {
        final list = await searchMovies(kw, page: 1);
        for (final m in list) {
          if (m.id == movieId) continue;
          if (seen.contains(m.id)) continue;
          seen.add(m.id);
          out.add(m);
          if (out.length >= 10) return;
        }
      } catch (e) {
        debugPrint('推荐搜索失败 keyword=$kw: $e');
      }
    }

    if (movie.name.trim().length >= 2) {
      await tryKeyword(movie.name.trim());
    }

    final baseTitle = stripSeasonFromTitleForRecommend(movie.name);
    if (baseTitle.length >= 2 && baseTitle != movie.name.trim()) {
      await tryKeyword(baseTitle);
    }

    if (out.length < 6 && movie.alias.trim().length >= 2) {
      await tryKeyword(movie.alias.trim());
    }

    for (final g in movie.genres) {
      for (final part in g.split(RegExp(r'[,，/、]'))) {
        await tryKeyword(part);
        if (out.length >= 10) return List<Movie>.from(out);
      }
    }

    if (out.length < 4 && movie.director.trim().length >= 2) {
      await tryKeyword(movie.director.trim());
    }

    return out.take(10).toList();
  }

  /// 获取影片推荐（先拉详情再走 [getDetailSideRecommendations]）
  Future<List<Movie>> getRecommendations(String movieId) async {
    if (_currentSource == null) return [];

    try {
      final movie = await getMovieDetail(movieId);
      if (movie == null) return [];
      return getDetailSideRecommendations(movie);
    } catch (e) {
      debugPrint('获取推荐失败: $e');
      return [];
    }
  }

  /// 多源聚合获取影片详情
  ///
  /// 通过影片名称在所有源中搜索，找到匹配的影片。
  /// 参考 searchFromAllSources 的实现模式，使用并发请求 + Stream 流式返回。
  /// 对每个源返回的搜索结果，尝试匹配目标影片（名称标准化后一致）。
  Stream<MultiDetailEvent> fetchMovieFromAllSources(
    String movieName, {
    List<PlaySource>? sources,
  }) async* {
    if (movieName.trim().isEmpty) {
      yield MultiDetailComplete(allResults: []);
      return;
    }

    // 如果没有传入源列表，使用所有已启用的默认源（此处由调用方传入，避免内部依赖 Provider）
    final targetSources = sources ?? [];
    if (targetSources.isEmpty) {
      yield MultiDetailComplete(allResults: []);
      return;
    }

    final allResults = <SourceDetailFound>[];

    // 并发请求所有源
    await for (final event
        in _searchSourcesConcurrently(targetSources, movieName, 1)) {
      if (event.error != null) {
        debugPrint('多源详情聚合: 源 "${event.source.name}" 搜索失败: ${event.error}');
        yield SourceDetailNotFound(source: event.source);
        continue;
      }

      // 在搜索结果中找到匹配的影片
      final matchedMovie = _findMatchingMovie(event.movies, movieName);
      if (matchedMovie != null) {
        // 获取匹配影片的完整详情（包含播放线路）
        final detailMovie =
            await _fetchDetailForSource(event.source, matchedMovie);
        if (detailMovie != null) {
          final found =
              SourceDetailFound(source: event.source, movie: detailMovie);
          allResults.add(found);
          yield found;
        } else {
          yield SourceDetailNotFound(source: event.source);
        }
      } else {
        yield SourceDetailNotFound(source: event.source);
      }
    }

    yield MultiDetailComplete(allResults: allResults);
  }

  /// 在搜索结果中找到匹配目标名称的影片
  ///
  /// 使用名称标准化匹配，优先匹配完全一致的，其次匹配包含关系的。
  Movie? _findMatchingMovie(List<Movie> movies, String targetName) {
    if (movies.isEmpty) return null;

    final normalizedTarget = _normalizeName(targetName);

    // 第一轮：完全匹配（标准化后一致）
    for (final movie in movies) {
      if (_normalizeName(movie.name) == normalizedTarget) {
        return movie;
      }
    }

    // 第二轮：包含匹配（目标名称包含在搜索结果名称中，或反过来）
    for (final movie in movies) {
      final normalizedName = _normalizeName(movie.name);
      if (normalizedName.contains(normalizedTarget) ||
          normalizedTarget.contains(normalizedName)) {
        return movie;
      }
    }

    return null;
  }

  /// 获取指定源中某部影片的完整详情
  ///
  /// 临时切换到目标源，通过影片ID获取完整详情（包含播放线路），
  /// 获取完成后恢复原来的源。
  Future<Movie?> _fetchDetailForSource(PlaySource source, Movie movie) async {
    final previousSource = _currentSource;

    try {
      _currentSource = source;
      final detail = await getMovieDetail(movie.id, allowFallback: false);
      return detail;
    } catch (e) {
      debugPrint('获取源 "${source.name}" 的影片详情失败: $e');
      return null;
    } finally {
      _currentSource = previousSource;
    }
  }

  /// 多源并发搜索
  ///
  /// 并发请求所有已启用的源，通过 Stream 流式返回结果。
  /// 源列表由调用方通过 [sources] 参数传入，避免 ApiService 内部依赖 Provider。
  Stream<MultiSourceSearchEvent> searchFromAllSources(
    String keyword, {
    required List<PlaySource> sources,
    int page = 1,
  }) async* {
    if (keyword.trim().isEmpty || sources.isEmpty) {
      yield MultiSourceSearchProgress(
        completed: 0,
        total: 0,
        results: [],
      );
      return;
    }

    int completedCount = 0;
    final allResults = <Movie>[];

    // 先发送初始进度事件
    yield MultiSourceSearchProgress(
      completed: 0,
      total: sources.length,
      results: allResults,
    );

    // 并发请求所有源，谁先返回谁先处理
    await for (final event
        in _searchSourcesConcurrently(sources, keyword, page)) {
      if (event.error != null) {
        debugPrint('源 "${event.source.name}" 搜索失败: ${event.error}');
      }

      final beforeLen = allResults.length;
      _mergeMultiSourceSearchResults(allResults, event.movies, event.source);
      completedCount++;

      yield MultiSourceSearchProgress(
        completed: completedCount,
        total: sources.length,
        results: List<Movie>.from(allResults),
        newMovies: allResults.length > beforeLen
            ? allResults.sublist(beforeLen)
            : const [],
      );
    }
  }

  /// 并发请求多个源
  ///
  /// 为每个源创建一个异步任务，通过 StreamController 合并结果。
  /// 谁先返回谁先 yield，实现流式效果。
  /// 最大并发请求数
  static const _maxConcurrent = 4;

  Stream<SourceSearchResult> _searchSourcesConcurrently(
    List<PlaySource> sources,
    String keyword,
    int page,
  ) async* {
    final controllers = <StreamController<SourceSearchResult>>[];
    int running = 0;
    int index = 0;
    final completer = Completer<void>();

    void startNext() {
      while (running < _maxConcurrent && index < sources.length) {
        final source = sources[index++];
        final controller = StreamController<SourceSearchResult>();
        controllers.add(controller);
        running++;

        _searchSingleSource(source, keyword, page).then((movies) {
          controller.add(SourceSearchResult(source: source, movies: movies));
          controller.close();
        }).catchError((e) {
          controller.add(
            SourceSearchResult(
              source: source,
              movies: [],
              error: e.toString(),
            ),
          );
          controller.close();
        }).whenComplete(() {
          running--;
          startNext();
          if (running == 0 &&
              index >= sources.length &&
              !completer.isCompleted) {
            completer.complete();
          }
        });
      }
    }

    startNext();

    // 合并所有 stream（谁先返回谁先 yield）
    await for (final event in _mergeStreams(controllers)) {
      yield event;
    }
  }

  /// 搜索单个源
  ///
  /// 临时切换到指定源进行搜索，搜索完成后恢复原来的源。
  Future<List<Movie>> _searchSingleSource(
    PlaySource source,
    String keyword,
    int page,
  ) async {
    // 保存当前源
    final previousSource = _currentSource;

    try {
      // 临时切换到目标源
      _currentSource = source;
      final movies = await searchMovies(keyword, page: page);
      final sid = source.id;
      return movies
          .map((m) => m.sourceId.isEmpty ? m.copyWith(sourceId: sid) : m)
          .toList();
    } catch (e) {
      debugPrint('搜索源 "${source.name}" 失败: $e');
      rethrow;
    } finally {
      // 恢复原来的源
      _currentSource = previousSource;
    }
  }

  /// 合并多个 StreamController 为一个 Stream
  ///
  /// 使用 StreamGroup 的思路：监听所有 controller，
  /// 任何一个有数据就立即 yield。
  Stream<SourceSearchResult> _mergeStreams(
    List<StreamController<SourceSearchResult>> controllers,
  ) async* {
    if (controllers.isEmpty) return;

    int closedCount = 0;
    final total = controllers.length;
    final completer = Completer<void>();
    final eventQueue = StreamController<SourceSearchResult>.broadcast();

    // 为每个 controller 设置监听
    for (final controller in controllers) {
      controller.stream.listen(
        (event) {
          if (!eventQueue.isClosed) {
            eventQueue.add(event);
          }
        },
        onError: (e) {
          debugPrint('Stream 合并错误: $e');
        },
        onDone: () {
          closedCount++;
          if (closedCount >= total && !completer.isCompleted) {
            completer.complete();
            // 关闭事件队列，使 await for 循环能够退出
            if (!eventQueue.isClosed) {
              eventQueue.close();
            }
          }
        },
      );
    }

    // 使用 await for 消费事件队列（eventQueue 在所有 controller 完成时关闭）
    await for (final event in eventQueue.stream) {
      yield event;
    }
  }

  /// 多源搜索合并：同款影片只保留一行，并把其它源的 [MovieAlternateSource] 记在首条上。
  void _mergeMultiSourceSearchResults(
    List<Movie> allResults,
    List<Movie> newMovies,
    PlaySource source,
  ) {
    for (final raw in newMovies) {
      final movie =
          raw.sourceId.isEmpty ? raw.copyWith(sourceId: source.id) : raw;

      final idx = allResults.indexWhere((e) => _isSameMovie(e, movie));
      if (idx < 0) {
        allResults.add(movie);
        continue;
      }

      final keeper = allResults[idx];
      if (keeper.id == movie.id && keeper.sourceId == movie.sourceId) {
        continue;
      }
      if (keeper.sourceId == movie.sourceId) {
        continue;
      }
      final exists = keeper.alternateSources.any(
        (a) => a.sourceId == movie.sourceId && a.movieId == movie.id,
      );
      if (exists) continue;

      allResults[idx] = keeper.copyWith(
        alternateSources: [
          ...keeper.alternateSources,
          MovieAlternateSource(
            sourceId: movie.sourceId,
            movieId: movie.id,
            sourceDisplayName: source.name,
          ),
        ],
      );
    }
  }

  /// 判断是否为同一部影片（严格匹配）
  ///
  /// 规则：名称标准化后一致 + 年份一致 + 类型有交集
  bool _isSameMovie(Movie a, Movie b) {
    // 名称标准化比较（去除空格和特殊字符）
    final nameA = _normalizeName(a.name);
    final nameB = _normalizeName(b.name);
    if (nameA != nameB) return false;

    // 年份比较（如果双方都有年份）
    if (a.year.isNotEmpty && b.year.isNotEmpty && a.year != b.year) {
      return false;
    }

    // 类型比较（如果双方都有类型，取交集判断）
    if (a.genres.isNotEmpty && b.genres.isNotEmpty) {
      final hasOverlap = a.genres.any((g) => b.genres.contains(g));
      if (!hasOverlap) return false;
    }

    return true;
  }

  /// 标准化影片名称（去除空格、特殊字符、季数后缀等）
  String _normalizeName(String name) {
    return name
        .replaceAll(RegExp(r'\s+'), '') // 去除空格
        .replaceAll(RegExp(r'[·\-_:：]'), '') // 去除常见分隔符
        .replaceAll(RegExp(r'第[一二三四五六七八九十\d]+季'), '') // 去除季数后缀
        .replaceAll(RegExp(r'第[一二三四五六七八九十\d]+部'), '') // 去除部数后缀
        .toLowerCase();
  }
}

/// 首页数据
class HomeData {
  /// 轮播图列表
  final List<Movie> bannerList;

  /// 热门推荐
  final List<Movie> hotMovies;

  /// 最近更新
  final List<Movie> latestMovies;

  /// 高分榜单
  final List<Movie> topRatedMovies;

  /// 经典合集
  final List<Movie> classicMovies;

  HomeData({
    this.bannerList = const [],
    this.hotMovies = const [],
    this.latestMovies = const [],
    this.topRatedMovies = const [],
    this.classicMovies = const [],
  });

  /// 无数据时返回空状态（使用mock数据展示）
  factory HomeData.empty() {
    return HomeData(
      bannerList: _generateMockMovies(5),
      hotMovies: _generateMockMovies(10),
      latestMovies: _generateMockMovies(10),
      topRatedMovies: _generateMockMovies(10),
      classicMovies: _generateMockMovies(10),
    );
  }

  /// 生成模拟数据（用于无源时的展示）
  static List<Movie> _generateMockMovies(int count) {
    final movies = <Movie>[];
    for (int i = 0; i < count; i++) {
      movies.add(
        Movie(
          id: 'mock_$i',
          name: '示例影片 ${i + 1}',
          cover: '',
          rating: (7.0 + (i % 3)).toDouble(),
          genres: ['动作', '科幻'],
          year: '2024',
          updateStatus: i % 2 == 0 ? '已完结' : '更新至第${i + 1}集',
        ),
      );
    }
    return movies;
  }
}

/// 多源搜索事件（基类）
abstract class MultiSourceSearchEvent {}

/// 多源详情聚合事件（基类）
abstract class MultiDetailEvent {}

/// 找到一个源的匹配影片
class SourceDetailFound extends MultiDetailEvent {
  /// 搜索的源
  final PlaySource source;

  /// 匹配到的影片详情
  final Movie movie;

  SourceDetailFound({required this.source, required this.movie});
}

/// 某个源搜索完成但未找到匹配
class SourceDetailNotFound extends MultiDetailEvent {
  /// 搜索的源
  final PlaySource source;

  SourceDetailNotFound({required this.source});
}

/// 所有源搜索完成
class MultiDetailComplete extends MultiDetailEvent {
  /// 所有成功匹配的结果
  final List<SourceDetailFound> allResults;

  MultiDetailComplete({required this.allResults});
}

/// 搜索进度事件
///
/// 每当有源返回结果时，都会发送一个进度事件，
/// UI 可以据此更新搜索结果列表和进度提示。
class MultiSourceSearchProgress extends MultiSourceSearchEvent {
  /// 已完成的源数量
  final int completed;

  /// 源总数
  final int total;

  /// 当前所有去重后的搜索结果
  final List<Movie> results;

  /// 本次新增的影片（用于UI动画效果）
  final List<Movie> newMovies;

  MultiSourceSearchProgress({
    required this.completed,
    required this.total,
    required this.results,
    this.newMovies = const [],
  });

  /// 是否所有源都已搜索完毕
  bool get isFinished => completed >= total;

  /// 搜索状态文本（用于底部进度提示）
  String get statusText {
    final multi = results.where((m) => m.alternateSources.isNotEmpty).length;
    if (multi > 0) {
      return '已搜索 $completed/$total 个源，共 ${results.length} 条结果（$multi 条在多个源有资源，卡片内可切换来源）';
    }
    return '已搜索 $completed/$total 个源，共找到 ${results.length} 部';
  }
}

/// 单个源的搜索结果
class SourceSearchResult {
  /// 搜索的源
  final PlaySource source;

  /// 该源返回的影片列表
  final List<Movie> movies;

  /// 错误信息（如果搜索失败）
  final String? error;

  SourceSearchResult({
    required this.source,
    required this.movies,
    this.error,
  });
}
